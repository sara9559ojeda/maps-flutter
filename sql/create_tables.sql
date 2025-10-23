-- Schema for safety reports and risk zones

-- Reports table ------------------------------------------------------------
CREATE TABLE IF NOT EXISTS reports (
    id SERIAL PRIMARY KEY,
    user_id UUID NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
    latitude DOUBLE PRECISION NOT NULL,
    longitude DOUBLE PRECISION NOT NULL,
    risk_level INTEGER NOT NULL CHECK (risk_level BETWEEN 1 AND 3),
    description TEXT,
    grid_key TEXT NOT NULL,
    created_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_reports_lat_lng ON reports USING gist (point(longitude, latitude));
CREATE INDEX IF NOT EXISTS idx_reports_grid_key ON reports (grid_key);

-- Updated_at helper --------------------------------------------------------
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reports_updated_at
BEFORE UPDATE ON reports
FOR EACH ROW
EXECUTE FUNCTION update_updated_at_column();

-- Zone helpers -------------------------------------------------------------
CREATE OR REPLACE FUNCTION calculate_zone_info(
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION
)
RETURNS TABLE (grid_key TEXT, center_latitude DOUBLE PRECISION, center_longitude DOUBLE PRECISION)
AS $$
DECLARE
    grid_size CONSTANT DOUBLE PRECISION := 0.003; -- ~330 m cells
    lat_index BIGINT;
    lng_index BIGINT;
BEGIN
    lat_index := FLOOR(lat / grid_size)::BIGINT;
    lng_index := FLOOR(lng / grid_size)::BIGINT;

    grid_key := lat_index::TEXT || '_' || lng_index::TEXT;
    center_latitude := (lat_index::DOUBLE PRECISION + 0.5) * grid_size;
    center_longitude := (lng_index::DOUBLE PRECISION + 0.5) * grid_size;
    RETURN NEXT;
END;
$$ LANGUAGE plpgsql IMMUTABLE;

CREATE OR REPLACE FUNCTION set_report_zone_metadata()
RETURNS TRIGGER AS $$
DECLARE
    zone RECORD;
BEGIN
    SELECT * INTO zone FROM calculate_zone_info(NEW.latitude, NEW.longitude);
    NEW.grid_key := zone.grid_key;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reports_set_zone
BEFORE INSERT OR UPDATE OF latitude, longitude ON reports
FOR EACH ROW
EXECUTE FUNCTION set_report_zone_metadata();

-- Zones table --------------------------------------------------------------
CREATE TABLE IF NOT EXISTS zones (
    id SERIAL PRIMARY KEY,
    grid_key TEXT UNIQUE NOT NULL,
    center_latitude DOUBLE PRECISION NOT NULL,
    center_longitude DOUBLE PRECISION NOT NULL,
    average_risk NUMERIC(4,2) NOT NULL DEFAULT 0,
    report_count INTEGER NOT NULL DEFAULT 0,
    updated_at TIMESTAMP WITH TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_zones_center ON zones USING gist (point(center_longitude, center_latitude));

CREATE OR REPLACE FUNCTION ensure_zone_exists(
    p_grid_key TEXT,
    lat DOUBLE PRECISION,
    lng DOUBLE PRECISION
)
RETURNS VOID AS $$
DECLARE
    zone RECORD;
BEGIN
    SELECT * INTO zone FROM calculate_zone_info(lat, lng);
    IF zone.grid_key <> p_grid_key THEN
        RAISE EXCEPTION 'Zone key mismatch: expected %, received %', zone.grid_key, p_grid_key;
    END IF;

    INSERT INTO zones (grid_key, center_latitude, center_longitude)
    VALUES (zone.grid_key, zone.center_latitude, zone.center_longitude)
    ON CONFLICT (grid_key) DO UPDATE
        SET center_latitude = EXCLUDED.center_latitude,
            center_longitude = EXCLUDED.center_longitude;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION refresh_zone_metrics(p_grid_key TEXT)
RETURNS VOID AS $$
DECLARE
    v_avg NUMERIC(4,2);
    v_count INTEGER;
BEGIN
    SELECT
        COALESCE(AVG(risk_level)::NUMERIC(4,2), 0),
        COUNT(*)
    INTO v_avg, v_count
    FROM reports
    WHERE grid_key = p_grid_key;

    IF v_count = 0 THEN
        DELETE FROM zones WHERE grid_key = p_grid_key;
    ELSE
        UPDATE zones
        SET average_risk = v_avg,
            report_count = v_count,
            updated_at = NOW()
        WHERE grid_key = p_grid_key;
    END IF;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_zone_on_insert()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM ensure_zone_exists(NEW.grid_key, NEW.latitude, NEW.longitude);
    PERFORM refresh_zone_metrics(NEW.grid_key);
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_zone_on_update()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM ensure_zone_exists(NEW.grid_key, NEW.latitude, NEW.longitude);
    PERFORM refresh_zone_metrics(NEW.grid_key);
    IF NEW.grid_key <> OLD.grid_key THEN
        PERFORM refresh_zone_metrics(OLD.grid_key);
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE OR REPLACE FUNCTION sync_zone_on_delete()
RETURNS TRIGGER AS $$
BEGIN
    PERFORM refresh_zone_metrics(OLD.grid_key);
    RETURN OLD;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_reports_after_insert
AFTER INSERT ON reports
FOR EACH ROW
EXECUTE FUNCTION sync_zone_on_insert();

CREATE TRIGGER trg_reports_after_update
AFTER UPDATE ON reports
FOR EACH ROW
EXECUTE FUNCTION sync_zone_on_update();

CREATE TRIGGER trg_reports_after_delete
AFTER DELETE ON reports
FOR EACH ROW
EXECUTE FUNCTION sync_zone_on_delete();

-- Row level security -------------------------------------------------------
ALTER TABLE reports ENABLE ROW LEVEL SECURITY;
ALTER TABLE zones ENABLE ROW LEVEL SECURITY;

CREATE POLICY "Users can insert their own reports" ON reports
    FOR INSERT WITH CHECK (auth.uid() = user_id);

CREATE POLICY "Users can view all reports" ON reports
    FOR SELECT USING (TRUE);

CREATE POLICY "Users can update their own reports" ON reports
    FOR UPDATE USING (auth.uid() = user_id);

CREATE POLICY "Users can delete their own reports" ON reports
    FOR DELETE USING (auth.uid() = user_id);

CREATE POLICY "Everyone can read zones" ON zones
    FOR SELECT USING (TRUE);

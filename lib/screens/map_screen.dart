import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../models/report.dart';
import '../models/zone.dart';
import '../services/supabase_service.dart';
import '../providers/auth_provider.dart';

class MapScreen extends StatefulWidget {
  const MapScreen({super.key});

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> {
  static const LatLng _defaultCenter = LatLng(1.218545779510911, -77.28960274120831);
  static const double _zoneRadiusMeters = 220;
  final MapController _mapController = MapController();
  StreamSubscription<List<Report>>? _reportsSubscription;
  StreamSubscription<List<Zone>>? _zonesSubscription;
  List<Report> _reports = [];
  List<Zone> _zones = [];
  LatLng? _selectionMarker;
  bool _isSelectingLocation = false;
  void Function(LatLng position)? _onLocationPicked;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _subscribeToStreams();
  }

  @override
  void dispose() {
    _reportsSubscription?.cancel();
    _zonesSubscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Safety Zones Map'),
        actions: [
          IconButton(
            tooltip: 'Actualizar',
            icon: const Icon(Icons.refresh),
            onPressed: _isLoading ? null : _refreshData,
          ),
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: () => Provider.of<AuthProvider>(context, listen: false).signOut(),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : FlutterMap(
              mapController: _mapController,
              options: MapOptions(
                initialCenter: _defaultCenter,
                initialZoom: 13.0,
                onTap: (tapPosition, latLng) => _handleMapTap(latLng),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                  subdomains: const ['a', 'b', 'c'],
                ),
                CircleLayer(
                  circles: _buildZoneCircles(),
                ),
                MarkerLayer(
                  markers: [
                    ..._buildMarkers(),
                    if (_selectionMarker != null)
                      Marker(
                        point: _selectionMarker!,
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        child: const Icon(
                          Icons.place,
                          color: Colors.blueAccent,
                          size: 42,
                        ),
                      ),
                  ],
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addReport,
        child: const Icon(Icons.add),
      ),
    );
  }

  List<Marker> _buildMarkers() {
    return _reports.map((report) {
      return Marker(
        point: report.position,
        width: 40,
        height: 40,
        alignment: Alignment.center,
        child: Container(
          decoration: BoxDecoration(
            color: report.color,
            shape: BoxShape.circle,
          ),
          child: const Icon(Icons.location_pin, color: Colors.white, size: 24),
        ),
      );
    }).toList();
  }

  List<CircleMarker> _buildZoneCircles() {
    return _zones.map((zone) {
      final borderColor = switch (zone.riskLevel) {
        RiskLevel.low => Colors.green.shade600,
        RiskLevel.medium => Colors.orange.shade600,
        RiskLevel.high => Colors.red.shade600,
      };
      return CircleMarker(
        point: zone.center,
        color: zone.color,
        borderStrokeWidth: 2,
        borderColor: borderColor,
        useRadiusInMeter: true,
        radius: _zoneRadiusMeters,
      );
    }).toList();
  }

  void _handleMapTap(LatLng position) {
    if (!_isSelectingLocation) return;
    setState(() {
      _selectionMarker = position;
    });
    _onLocationPicked?.call(position);
  }

  Future<void> _loadInitialData() async {
    try {
      final results = await Future.wait([
        SupabaseService.getReports(),
        SupabaseService.getZones(),
      ]);
      if (!mounted) return;
      setState(() {
        _reports = results[0] as List<Report>;
        _zones = results[1] as List<Zone>;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('Error al cargar datos: $e');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _refreshData() async {
    setState(() => _isLoading = true);
    await _loadInitialData();
  }

  void _subscribeToStreams() {
    _reportsSubscription = SupabaseService.getReportsStream().listen(
      (reports) {
        if (!mounted) return;
        setState(() => _reports = reports);
      },
      onError: (error) => _showSnackBar('Error actualizando reportes: $error'),
    );
    _zonesSubscription = SupabaseService.getZonesStream().listen(
      (zones) {
        if (!mounted) return;
        setState(() => _zones = zones);
      },
      onError: (error) => _showSnackBar('Error actualizando zonas: $error'),
    );
  }

  void _addReport() {
    final userId = Provider.of<AuthProvider>(context, listen: false).userId;
    if (userId == null) {
      _showSnackBar('Debes iniciar sesión para crear un reporte.');
      return;
    }

    final descriptionController = TextEditingController();
    RiskLevel selectedRiskLevel = RiskLevel.medium;
    LatLng selectedPosition = _mapController.camera.center;
    bool isSubmitting = false;

    setState(() {
      _isSelectingLocation = true;
      _selectionMarker = selectedPosition;
    });

    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 24,
            bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 16,
          ),
          child: StatefulBuilder(
            builder: (context, setModalState) {
              void updatePosition(LatLng position) {
                setModalState(() => selectedPosition = position);
                setState(() => _selectionMarker = position);
              }

              _onLocationPicked = updatePosition;

              Future<void> submit() async {
                if (isSubmitting) return;
                setModalState(() => isSubmitting = true);
                try {
                  await SupabaseService.addReport(
                    userId: userId,
                    latitude: selectedPosition.latitude,
                    longitude: selectedPosition.longitude,
                    riskLevel: selectedRiskLevel,
                    description: descriptionController.text.trim().isEmpty
                        ? null
                        : descriptionController.text.trim(),
                  );
                  if (context.mounted) {
                    Navigator.of(sheetContext).pop();
                    _showSnackBar('Reporte creado correctamente.');
                  }
                } catch (e) {
                  setModalState(() => isSubmitting = false);
                  _showSnackBar('Error al crear el reporte: $e');
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    'Nuevo reporte',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<RiskLevel>(
                    initialValue: selectedRiskLevel,
                    decoration: const InputDecoration(
                      labelText: 'Nivel de riesgo',
                      border: OutlineInputBorder(),
                    ),
                    items: RiskLevel.values
                        .map(
                          (level) => DropdownMenuItem<RiskLevel>(
                            value: level,
                            child: Text(_riskLevelLabel(level)),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setModalState(() => selectedRiskLevel = value);
                    },
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: descriptionController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: 'Comentarios (opcional)',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Ubicación seleccionada',
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Toca el mapa para marcar un punto o usa el centro actual.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${selectedPosition.latitude.toStringAsFixed(6)}, ${selectedPosition.longitude.toStringAsFixed(6)}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () {
                        updatePosition(_mapController.camera.center);
                      },
                      icon: const Icon(Icons.my_location),
                      label: const Text('Usar centro del mapa'),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: isSubmitting ? null : submit,
                    icon: isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.check),
                    label: Text(isSubmitting ? 'Guardando...' : 'Guardar reporte'),
                  ),
                ],
              );
            },
          ),
        );
      },
    ).whenComplete(() {
      descriptionController.dispose();
      _onLocationPicked = null;
      if (mounted) {
        setState(() {
          _isSelectingLocation = false;
          _selectionMarker = null;
        });
      } else {
        _isSelectingLocation = false;
        _selectionMarker = null;
      }
    });
  }

  void _showSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }

  static String _riskLevelLabel(RiskLevel level) {
    return switch (level) {
      RiskLevel.low => '🟢 Zona segura',
      RiskLevel.medium => '🟡 Riesgo medio',
      RiskLevel.high => '🔴 Zona peligrosa',
    };
  }
}

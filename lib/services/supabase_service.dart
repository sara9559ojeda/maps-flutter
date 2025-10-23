import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/report.dart';
import '../models/zone.dart';

class SupabaseService {
  static SupabaseClient get client => Supabase.instance.client;

  static String get _supabaseUrl => _readEnvVar('SUPABASE_URL');
  static String get _supabaseAnonKey => _readEnvVar('SUPABASE_ANON_KEY');

  static Future<void> initialize() async {
    await Supabase.initialize(
      url: _supabaseUrl,
      anonKey: _supabaseAnonKey,
    );
  }

  static String _readEnvVar(String key) {
    final value = dotenv.maybeGet(key);
    if (value == null || value.isEmpty) {
      throw StateError('Falta la variable de entorno $key en .env');
    }
    return value;
  }

  // Authentication methods
  static Future<AuthResponse> signUp(String email, String password) async {
    return await client.auth.signUp(
      email: email,
      password: password,
    );
  }

  static Future<AuthResponse> signIn(String email, String password) async {
    return await client.auth.signInWithPassword(
      email: email,
      password: password,
    );
  }

  static Future<void> signOut() async {
    await client.auth.signOut();
  }

  static User? get currentUser => client.auth.currentUser;

  static Stream<AuthState> get authStateChanges => client.auth.onAuthStateChange;

  // Reports methods
  static Future<List<Report>> getReports() async {
    final response = await client.from('reports').select();
    return (response as List).map((json) => Report.fromJson(json)).toList();
  }

  static Future<void> addReport({
    required String userId,
    required double latitude,
    required double longitude,
    required RiskLevel riskLevel,
    String? description,
  }) async {
    await client.from('reports').insert({
      'user_id': userId,
      'latitude': latitude,
      'longitude': longitude,
      'risk_level': riskLevel.index + 1,
      'description': description,
    });
  }

  static Stream<List<Report>> getReportsStream() {
    return client.from('reports').stream(primaryKey: ['id']).asyncMap((rows) async {
      return rows.map((row) => Report.fromJson(row)).toList();
    });
  }

  // Zones methods
  static Future<List<Zone>> getZones() async {
    final response = await client.from('zones').select();
    return (response as List).map((json) => Zone.fromJson(json)).toList();
  }

  static Stream<List<Zone>> getZonesStream() {
    return client.from('zones').stream(primaryKey: ['id']).asyncMap((rows) async {
      return rows.map((row) => Zone.fromJson(row)).toList();
    });
  }
}

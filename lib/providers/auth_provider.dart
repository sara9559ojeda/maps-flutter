import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/supabase_service.dart';

class AuthProvider with ChangeNotifier {
  bool _isAuthenticated = false;
  String? _userId;

  bool get isAuthenticated => _isAuthenticated;
  String? get userId => _userId;

  AuthProvider() {
    _checkAuthState();
    SupabaseService.authStateChanges.listen(_onAuthStateChange);
  }

  void _checkAuthState() {
    final user = SupabaseService.currentUser;
    _isAuthenticated = user != null;
    _userId = user?.id;
    notifyListeners();
  }

  void _onAuthStateChange(AuthState authState) {
    _checkAuthState();
  }

  Future<void> signUp(String email, String password) async {
    await SupabaseService.signUp(email, password);
  }

  Future<void> signIn(String email, String password) async {
    await SupabaseService.signIn(email, password);
  }

  Future<void> signOut() async {
    await SupabaseService.signOut();
  }
}

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class AuthService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;

  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => currentUser != null;

  // Login method
  Future<AuthResponse> signInWithEmail(String email, String password) async {
    try {
      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      notifyListeners();
      return response;
    } catch (e) {
      throw e;
    }
  }

  // Register method
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String role,
    required String evRegistrationNo,
  }) async {
    try {
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );

      if (response.user != null) {
        // Insert user data into users table
        await _supabase.from('users').insert({
          'userid': response.user!.id,
          'email': email,
          'name': name,
          'role': role,
          'ev_registration_no': evRegistrationNo,
          'status': 'active',
          'created_at': DateTime.now().toIso8601String(),
        });
      }

      notifyListeners();
      return response;
    } catch (e) {
      throw e;
    }
  }

  // Logout method
  Future<void> signOut() async {
    await _supabase.auth.signOut();
    notifyListeners();
  }

  // Password reset
  Future<void> resetPassword(String email) async {
    await _supabase.auth.resetPasswordForEmail(email);
  }
}

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
      throw Exception('Failed to login: $e');
    }
  }

  // Register method
  Future<AuthResponse> signUpWithEmail({
    required String email,
    required String password,
    required String name,
    required String role,
    String? evRegistrationNo,
    String? evType,
    String? agency,
    String? plateNumber,
  }) async {
    try {
      // Step 1: Create the auth account
      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      if (response.user == null) return response; // If signup fails

      // Step 2: If the role is "Driver", ensure EmergencyVehicle exists
      if (role.toLowerCase() == 'driver' && evRegistrationNo != null) {
        // Check if the Emergency Vehicle already exists
        final existingEV = await _supabase
            .from('emergencyvehicle')
            .select()
            .eq('ev_registration_no', evRegistrationNo)
            .maybeSingle();  // Use maybeSingle instead of single

        // If not, insert a new emergency vehicle
        if (existingEV == null) {
          await _supabase.from('emergencyvehicle').upsert({
            'ev_registration_no': evRegistrationNo,
            'ev_type': evType ?? '',
            'agency': agency ?? '',
            'plate_number': plateNumber ?? '',
          });
        }
      }

      // Step 3: Insert user data into users table
      final userId = response.user!.id;
      await _supabase.from('users').upsert({
        'userid': userId,  // Ensure UUID is treated as a string
        'email': email,
        'name': name,
        'role': role,
        'ev_registration_no': (role.toLowerCase() == 'driver') ? evRegistrationNo : null,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      }).eq('userid', userId);  // Handle conflicts based on `userid`

      notifyListeners();
      return response;
    } catch (e) {
      throw Exception('Failed to sign up: $e');
    }
  }

  // Logout method
  Future<void> signOut() async {
    try {
      await _supabase.auth.signOut();
      notifyListeners();
    } catch (e) {
      throw Exception('Failed to logout: $e');
    }
  }

  // Password reset method
  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      throw Exception('Failed to reset password: $e');
    }
  }
}

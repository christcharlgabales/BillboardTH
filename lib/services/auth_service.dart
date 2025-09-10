import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/foundation.dart' show kIsWeb;

class AuthService extends ChangeNotifier {
  final _supabase = Supabase.instance.client;
  String? _userRole;
  bool _isLoading = false;

  User? get currentUser => _supabase.auth.currentUser;
  bool get isLoggedIn => currentUser != null;
  String? get userRole => _userRole;
  bool get isLoading => _isLoading;
  bool get isAdmin => _userRole?.toLowerCase() == 'administrator';

  Future<AuthResponse> signInWithEmail(String email, String password) async {
    try {
      _isLoading = true;
      notifyListeners();

      final response = await _supabase.auth.signInWithPassword(
        email: email,
        password: password,
      );
      
      if (response.user != null) {
        // Updated query to handle potential missing user data
        final userData = await _supabase
            .from('users')
            .select('role, userid')
            .eq('userid', response.user!.id)
            .maybeSingle(); // Changed from single() to maybeSingle()

        if (userData == null) {
          await signOut();
          throw Exception('User account not found');
        }
        
        _userRole = userData['role'];
        
        // Platform validation
        if ((_userRole?.toLowerCase() == 'administrator' && !kIsWeb) ||
            (_userRole?.toLowerCase() == 'driver' && kIsWeb)) {
          await signOut();
          throw Exception(
            _userRole?.toLowerCase() == 'administrator' 
              ? 'Administrator access is only available through web browser'
              : 'Driver access is only available through mobile app'
          );
        }
        
        notifyListeners();
      }
      
      return response;
    } catch (e) {
      throw Exception('Failed to login: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

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
      _isLoading = true;
      notifyListeners();

      if ((role.toLowerCase() == 'administrator' && !kIsWeb) ||
          (role.toLowerCase() == 'driver' && kIsWeb)) {
        throw Exception(
          role.toLowerCase() == 'administrator' 
            ? 'Administrator registration is only available through web browser'
            : 'Driver registration is only available through mobile app'
        );
      }

      final response = await _supabase.auth.signUp(
        email: email,
        password: password,
      );
      
      if (response.user == null) return response;

      if (role.toLowerCase() == 'driver' && evRegistrationNo != null) {
        final existingEV = await _supabase
            .from('emergencyvehicle')
            .select()
            .eq('ev_registration_no', evRegistrationNo)
            .maybeSingle();

        if (existingEV == null) {
          await _supabase.from('emergencyvehicle').upsert({
            'ev_registration_no': evRegistrationNo,
            'ev_type': evType ?? '',
            'agency': agency ?? '',
            'plate_number': plateNumber ?? '',
          });
        }
      }

      final userId = response.user!.id;
      await _supabase.from('users').upsert({
        'userid': userId,
        'email': email,
        'name': name,
        'role': role,
        'ev_registration_no': (role.toLowerCase() == 'driver') ? evRegistrationNo : null,
        'status': 'active',
        'created_at': DateTime.now().toIso8601String(),
      });

      _userRole = role;
      notifyListeners();
      return response;
    } catch (e) {
      throw Exception('Failed to sign up: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> signOut() async {
    try {
      _isLoading = true;
      notifyListeners();
      await _supabase.auth.signOut();
      _userRole = null;
    } catch (e) {
      throw Exception('Failed to logout: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> resetPassword(String email) async {
    try {
      await _supabase.auth.resetPasswordForEmail(email);
    } catch (e) {
      throw Exception('Failed to reset password: $e');
    }
  }

  Future<void> loadUserRole() async {
    try {
      if (currentUser != null) {
        final userData = await _supabase
            .from('users')
            .select('role')
            .eq('userid', currentUser!.id)
            .single();
        
        _userRole = userData['role'];
        notifyListeners();
      }
    } catch (e) {
      print('Error loading user role: $e');
    }
  }
}
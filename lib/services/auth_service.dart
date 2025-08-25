import 'package:supabase_flutter/supabase_flutter.dart';

final supabase = Supabase.instance.client;

/// Sign up a user in Supabase Auth + your `users` table.
/// If role == "Driver", upsert an EmergencyVehicle entry first.
class AuthService {
  static Future<String?> signUp({
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
      // 1) Create the auth account
      final authRes = await supabase.auth.signUp(email: email, password: password);
      if (authRes.user == null) return 'Signup failed.';

      // 2) If Driver, ensure EmergencyVehicle exists
      if (role.toLowerCase() == 'driver' && (evRegistrationNo ?? '').isNotEmpty) {
        await supabase.from('emergencyvehicle').upsert({
          'ev_registration_no': evRegistrationNo,
          'ev_type': evType ?? '',
          'agency': agency ?? '',
          'plate_number': plateNumber ?? '',
        }, onConflict: 'ev_registration_no');
      }

      // 3) Insert to custom users table
      await supabase.from('users').insert({
        'email': email,
        'password': password, // ⚠️ store hashed in production; kept to match your schema
        'name': name,
        'role': role,
        'ev_registration_no': role.toLowerCase() == 'driver' ? evRegistrationNo : null,
        'status': 'active',
      });

      return null;
    } on PostgrestException catch (e) {
      return e.message;
    } catch (e) {
      return e.toString();
    }
  }

  static Future<Map<String, dynamic>?> login({
    required String email,
    required String password,
  }) async {
    try {
      final res = await supabase.auth.signInWithPassword(email: email, password: password);
      if (res.user == null) return null;

      final profile = await supabase
          .from('users')
          .select()
          .eq('email', email)
          .maybeSingle();

      return profile;
    } on AuthException catch (e) {
      throw Exception(e.message);
    } on PostgrestException catch (e) {
      throw Exception(e.message);
    } catch (e) {
      throw Exception(e.toString());
    }
  }

  static Future<void> signOut() async {
    await supabase.auth.signOut();
  }
}

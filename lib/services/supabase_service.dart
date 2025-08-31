import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/billboard.dart';
import '../models/emergency_vehicle.dart';
import '../models/user.dart';

class SupabaseService extends ChangeNotifier {
  final SupabaseClient _client = Supabase.instance.client;
  
  List<Billboard> _billboards = [];
  EmergencyVehicle? _currentVehicle;
  AppUser? _currentUser;

  List<Billboard> get billboards => _billboards;
  EmergencyVehicle? get currentVehicle => _currentVehicle;
  AppUser? get currentUser => _currentUser;

  Future<void> loadBillboards() async {
    try {
      final response = await _client.from('billboard').select();
      _billboards = (response as List)
          .map((json) => Billboard.fromJson(json))
          .toList();
      notifyListeners();
    } catch (e) {
      print('Error loading billboards: $e');
    }
  }

  Future<void> loadUserData(String email) async {
    try {
      final userResponse = await _client
          .from('users')
          .select()
          .eq('email', email)
          .single();
      
      _currentUser = AppUser.fromJson(userResponse);

      final vehicleResponse = await _client
          .from('emergencyvehicle')
          .select()
          .eq('ev_registration_no', _currentUser!.evRegistrationNo)
          .single();
      
      _currentVehicle = EmergencyVehicle.fromJson(vehicleResponse);
      notifyListeners();
    } catch (e) {
      print('Error loading user data: $e');
    }
  }

  Future<void> triggerAlert(int billboardId, String evRegistrationNo) async {
    try {
      await _client.from('alerts').insert({
        'ev_registration_no': evRegistrationNo,
        'billboard_id': billboardId,
        'triggered_at': DateTime.now().toIso8601String(),
      });

      await _client.from('alertlog').insert({
        'date': DateTime.now().toIso8601String().split('T')[0],
        'time': DateTime.now().toIso8601String().split('T')[1],
        'billboardid': billboardId,
        'ev_registration_no': evRegistrationNo,
        'type_of_activation': 'automatic',
        'result': 'success',
      });
    } catch (e) {
      print('Error triggering alert: $e');
    }
  }

  Future<void> manualActivation(int billboardId, String evRegistrationNo) async {
    try {
      await _client.from('alertlog').insert({
        'date': DateTime.now().toIso8601String().split('T')[0],
        'time': DateTime.now().toIso8601String().split('T')[1],
        'billboardid': billboardId,
        'ev_registration_no': evRegistrationNo,
        'type_of_activation': 'manual',
        'result': 'success',
      });
    } catch (e) {
      print('Error manual activation: $e');
    }
  }

  Future<List<Map<String, dynamic>>> getAlertLogs(String evRegistrationNo) async {
    try {
      final response = await _client
          .from('alertlog')
          .select()
          .eq('ev_registration_no', evRegistrationNo)
          .order('date', ascending: false)
          .limit(10);
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('Error getting alert logs: $e');
      return [];
    }
  }
}
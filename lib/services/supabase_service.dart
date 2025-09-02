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

  // Getters
  List<Billboard> get billboards => _billboards;
  EmergencyVehicle? get currentVehicle => _currentVehicle;
  AppUser? get currentUser => _currentUser;
  SupabaseClient get client => _client; // Added getter for client access

  // Load all billboards from database
  Future<void> loadBillboards() async {
    try {
      final response = await _client.from('billboard').select('*').order('billboardid');
      
      _billboards = (response as List<dynamic>).map((data) {
        return Billboard.fromJson({
          ...data,
          'isActivated': false, // Start with all billboards deactivated
        });
      }).toList();
      
      notifyListeners();
      print('✅ Loaded ${_billboards.length} billboards from database');
    } catch (e) {
      print('❌ Error loading billboards: $e');
      _billboards = []; // Ensure empty list on error
      notifyListeners();
    }
  }

  // Load user data by email
  Future<void> loadUserData(String email) async {
    try {
      // First, try to get user from users table
      final userResponse = await _client
          .from('users')
          .select('*')
          .eq('email', email)
          .maybeSingle(); // Use maybeSingle to handle null case
      
      if (userResponse != null) {
        _currentUser = AppUser.fromJson(userResponse);

        // Then get vehicle data using the registration number
        final vehicleResponse = await _client
            .from('emergencyvehicle')
            .select('*')
            .eq('ev_registration_no', _currentUser!.evRegistrationNo)
            .maybeSingle();
        
        if (vehicleResponse != null) {
          _currentVehicle = EmergencyVehicle.fromJson(vehicleResponse);
        }
      } else {
        // If no user found in users table, try to find directly in emergencyvehicle table
        final vehicleResponse = await _client
            .from('emergencyvehicle')
            .select('*')
            .eq('ev_registration_no', email) // Assuming email might be the registration number
            .maybeSingle();
        
        if (vehicleResponse != null) {
          _currentVehicle = EmergencyVehicle.fromJson(vehicleResponse);
          print('✅ Emergency vehicle data loaded directly: ${_currentVehicle!.evRegistrationNo}');
        }
      }
      
      notifyListeners();
      print('✅ User data loading completed for: $email');
    } catch (e) {
      print('❌ Error loading user data: $e');
    }
  }

  // Enhanced alert triggering with better error handling
  Future<bool> triggerAlert(int billboardId, String evRegistrationNo) async {
    try {
      // Insert into alerts table
      await _client.from('alerts').insert({
        'ev_registration_no': evRegistrationNo,
        'billboard_id': billboardId,
        'triggered_at': DateTime.now().toIso8601String(),
      });

      // Insert into alertlog table
      await _client.from('alertlog').insert({
        'date': DateTime.now().toIso8601String().split('T')[0],
        'time': DateTime.now().toIso8601String().split('T')[1].split('.')[0],
        'billboardid': billboardId,
        'ev_registration_no': evRegistrationNo,
        'type_of_activation': 'PROXIMITY_AUTO',
        'result': 'SUCCESS',
        'created_at': DateTime.now().toIso8601String(),
      });

      print('✅ Alert triggered successfully for Billboard $billboardId');
      return true;
    } catch (e) {
      print('❌ Error triggering alert: $e');
      
      // Try to log the failed attempt
      try {
        await _client.from('alertlog').insert({
          'date': DateTime.now().toIso8601String().split('T')[0],
          'time': DateTime.now().toIso8601String().split('T')[1].split('.')[0],
          'billboardid': billboardId,
          'ev_registration_no': evRegistrationNo,
          'type_of_activation': 'PROXIMITY_AUTO',
          'result': 'FAILED: $e',
          'created_at': DateTime.now().toIso8601String(),
        });
      } catch (logError) {
        print('❌ Error logging failed alert: $logError');
      }
      
      return false;
    }
  }

  // Enhanced manual activation
  Future<bool> manualActivation(int billboardId, String evRegistrationNo, bool isActivating) async {
    try {
      // Insert into alertlog table
      await _client.from('alertlog').insert({
        'date': DateTime.now().toIso8601String().split('T')[0],
        'time': DateTime.now().toIso8601String().split('T')[1].split('.')[0],
        'billboardid': billboardId,
        'ev_registration_no': evRegistrationNo,
        'type_of_activation': isActivating ? 'MANUAL_ACTIVATE' : 'MANUAL_DEACTIVATE',
        'result': 'SUCCESS',
        'created_at': DateTime.now().toIso8601String(),
      });

      // If manually activating, also add to alerts table
      if (isActivating) {
        await _client.from('alerts').insert({
          'ev_registration_no': evRegistrationNo,
          'billboard_id': billboardId,
          'triggered_at': DateTime.now().toIso8601String(),
        });
      }

      print('✅ Manual ${isActivating ? 'activation' : 'deactivation'} logged for Billboard $billboardId');
      return true;
    } catch (e) {
      print('❌ Error in manual activation: $e');
      return false;
    }
  }

  // Get alert logs for specific vehicle
  Future<List<Map<String, dynamic>>> getAlertLogs(String evRegistrationNo) async {
    try {
      final response = await _client
          .from('alertlog')
          .select('*')
          .eq('ev_registration_no', evRegistrationNo)
          .order('created_at', ascending: false)
          .limit(20); // Increased limit
      
      print('✅ Retrieved ${(response as List).length} alert logs');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error getting alert logs: $e');
      return [];
    }
  }

  // NEW: Get all alerts for debugging
  Future<List<Map<String, dynamic>>> getAllAlerts() async {
    try {
      final response = await _client
          .from('alerts')
          .select('*, billboard!inner(*)')
          .order('triggered_at', ascending: false)
          .limit(50);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching all alerts: $e');
      return [];
    }
  }

  // NEW: Get all alert logs for debugging
  Future<List<Map<String, dynamic>>> getAllAlertLogs() async {
    try {
      final response = await _client
          .from('alertlog')
          .select('*')
          .order('created_at', ascending: false)
          .limit(100);
      
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching alert logs: $e');
      return [];
    }
  }

  // NEW: Update billboard activation status in local state
  void updateBillboardStatus(int billboardId, bool isActivated) {
    final index = _billboards.indexWhere((b) => b.billboardId == billboardId);
    if (index != -1) {
      _billboards[index] = Billboard(
        billboardId: _billboards[index].billboardId,
        billboardNumber: _billboards[index].billboardNumber,
        location: _billboards[index].location,
        latitude: _billboards[index].latitude,
        longitude: _billboards[index].longitude,
        isActivated: isActivated,
      );
      notifyListeners();
    }
  }

  // NEW: Get billboard by ID
  Billboard? getBillboardById(int billboardId) {
    try {
      return _billboards.firstWhere((b) => b.billboardId == billboardId);
    } catch (e) {
      return null;
    }
  }

  // NEW: Get current emergency vehicle registration number
  String getCurrentEvRegistration() {
    if (_currentVehicle?.evRegistrationNo != null) {
      return _currentVehicle!.evRegistrationNo;
    } else if (_currentUser?.evRegistrationNo != null) {
      return _currentUser!.evRegistrationNo;
    } else {
      // Fallback to current user email
      final currentUser = Supabase.instance.client.auth.currentUser;
      return currentUser?.email ?? 'UNKNOWN';
    }
  }

  // NEW: Check database connection
  Future<bool> testConnection() async {
    try {
      await _client.from('billboard').select('count').limit(1);
      print('✅ Database connection successful');
      return true;
    } catch (e) {
      print('❌ Database connection failed: $e');
      return false;
    }
  }

  // NEW: Get statistics
  Future<Map<String, int>> getStatistics() async {
    try {
      final billboardCount = await _client
          .from('billboard')
          .select('count')
          .count(CountOption.exact);

      final alertCount = await _client
          .from('alerts')
          .select('count')
          .count(CountOption.exact);

      final vehicleCount = await _client
          .from('emergencyvehicle')
          .select('count')
          .count(CountOption.exact);

      return {
        'billboards': billboardCount.count,
        'alerts': alertCount.count,
        'vehicles': vehicleCount.count,
      };
    } catch (e) {
      print('❌ Error getting statistics: $e');
      return {
        'billboards': 0,
        'alerts': 0,
        'vehicles': 0,
      };
    }
  }
}
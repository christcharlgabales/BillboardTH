//supabase_service.dart

import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'package:path/path.dart' as path;
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
  SupabaseClient get client => _client;

  // Load all billboards from database
  Future<void> loadBillboards() async {
  try {
    // Step 1: Get all billboards from database
    final billboardResponse = await _client
        .from('billboard')
        .select('*')
        .order('billboardid');
    
    // Step 2: Get all currently active alerts
    final activeAlertsResponse = await _client
        .from('alerts')
        .select('billboard_id');
    
    final activeBillboardIds = Set<int>.from(
      activeAlertsResponse.map((alert) => alert['billboard_id'] as int)
    );
    
    print('Active billboard IDs from alerts table: $activeBillboardIds');
    
    // Step 3: Create billboard objects with correct activation status
    _billboards = (billboardResponse as List<dynamic>).map((data) {
      final billboardId = data['billboardid'] as int;
      final isActivated = activeBillboardIds.contains(billboardId);
      
      return Billboard.fromJson({
        ...data,
        'isActivated': isActivated, // Use real status from database
      });
    }).toList();
    
    notifyListeners();
    print('✅ Loaded ${_billboards.length} billboards from database');
    print('✅ Active billboards: ${_billboards.where((b) => b.isActivated).length}');
    print('✅ Inactive billboards: ${_billboards.where((b) => !b.isActivated).length}');
  } catch (e) {
    print('❌ Error loading billboards: $e');
    _billboards = []; // Ensure empty list on error
    notifyListeners();
  }
}


Future<bool> verifyEmergencyVehicle(String evRegistrationNo) async {
    try {
      final response = await _client
          .from('emergencyvehicle')
          .select()
          .eq('ev_registration_no', evRegistrationNo)
          .maybeSingle();
      
      if (response != null) {
        _currentVehicle = EmergencyVehicle.fromJson(response);
        notifyListeners();
        return true;
      }
      return false;
    } catch (e) {
      print('❌ Error verifying emergency vehicle: $e');
      return false;
    }
  }

Future<EmergencyVehicle?> getEmergencyVehicleDetails(String evRegistrationNo) async {
    try {
      final response = await _client
          .from('emergencyvehicle')
          .select()
          .eq('ev_registration_no', evRegistrationNo)
          .maybeSingle();
      
      if (response != null) {
        return EmergencyVehicle.fromJson(response);
      }
      return null;
    } catch (e) {
      print('❌ Error getting emergency vehicle details: $e');
      return null;
    }
  }



  @override
Future<void> loadUserData(String email) async {
  try {
    print('🔄 Loading user data for: $email');
    
    // First, try to get user from users table - handle multiple rows
    final userResponse = await _client
        .from('users')
        .select('*')
        .eq('email', email)
        .limit(1); // Limit to 1 row to avoid multiple rows issue
    
    if (userResponse.isNotEmpty) {
      // Take the first user if multiple exist
      _currentUser = AppUser.fromJson(userResponse.first);
      print('✅ User data loaded from users table: ${_currentUser!.name}');

      // If there are multiple users with same email, log a warning
      if (userResponse.length > 1) {
        print('⚠️ WARNING: Multiple users found with email $email. Using the first one.');
        print('⚠️ Consider cleaning up duplicate entries in the database.');
      }

      // Then get vehicle data using the registration number
      final vehicleResponse = await _client
          .from('emergencyvehicle')
          .select('*')
          .eq('ev_registration_no', _currentUser!.evRegistrationNo)
          .limit(1); // Also limit vehicle query
      
      if (vehicleResponse.isNotEmpty) {
        _currentVehicle = EmergencyVehicle.fromJson(vehicleResponse.first);
        print('✅ Emergency vehicle data loaded: ${_currentVehicle!.evRegistrationNo}');
        
        if (vehicleResponse.length > 1) {
          print('⚠️ WARNING: Multiple vehicles found with registration ${_currentUser!.evRegistrationNo}. Using the first one.');
        }
      } else {
        print('⚠️ No vehicle found for registration: ${_currentUser!.evRegistrationNo}');
      }
    } else {
      print('🔍 No user found in users table, trying emergencyvehicle table...');
      
      // If no user found in users table, try to find directly in emergencyvehicle table
      final vehicleResponse = await _client
          .from('emergencyvehicle')
          .select('*')
          .eq('ev_registration_no', email)
          .limit(1); // Limit this query too
      
      if (vehicleResponse.isNotEmpty) {
        _currentVehicle = EmergencyVehicle.fromJson(vehicleResponse.first);
        print('✅ Emergency vehicle data loaded directly: ${_currentVehicle!.evRegistrationNo}');
        
        if (vehicleResponse.length > 1) {
          print('⚠️ WARNING: Multiple vehicles found with registration $email. Using the first one.');
        }
      } else {
        print('⚠️ No data found in either users or emergencyvehicle table for: $email');
      }
    }

    // ✅ Cleanup after successful load
    if (_currentVehicle != null || _currentUser != null) {
      final evRegistration = getCurrentEvRegistration();
      await cleanupUserAlerts(evRegistration);
    }

    await cleanupExpiredAlerts();

    notifyListeners();
    print('✅ User data loading completed with cleanup for: $email');
    
  } catch (e) {
    print('❌ Error loading user data: $e');
    
    // Provide more detailed error information
    if (e is PostgrestException) {
      print('❌ PostgreSQL Error Details:');
      print('   Code: ${e.code}');
      print('   Message: ${e.message}');
      print('   Details: ${e.details}');
      print('   Hint: ${e.hint}');
    }
    
    // Clear any partially loaded data on error
    _currentUser = null;
    _currentVehicle = null;
    notifyListeners();
  }
}



Future<void> checkForDuplicates(String email) async {
  try {
    print('🔍 Checking for duplicate entries...');
    
    // Check users table
    final userDuplicates = await _client
        .from('users')
        .select('userid, name, email, ev_registration_no')
        .eq('email', email);
    
    if (userDuplicates.length > 1) {
      print('⚠️ DUPLICATE USERS FOUND:');
      for (int i = 0; i < userDuplicates.length; i++) {
        final user = userDuplicates[i];
        print('   User ${i + 1}: ID=${user['userid']}, Name=${user['name']}, EV=${user['ev_registration_no']}');
      }
      print('🔧 Recommendation: Clean up duplicate user entries in the database');
    }
    
    // If we have a current user, check for vehicle duplicates
    if (_currentUser != null) {
      final vehicleDuplicates = await _client
          .from('emergencyvehicle')
          .select('evid, ev_registration_no, ev_type')
          .eq('ev_registration_no', _currentUser!.evRegistrationNo);
      
      if (vehicleDuplicates.length > 1) {
        print('⚠️ DUPLICATE VEHICLES FOUND:');
        for (int i = 0; i < vehicleDuplicates.length; i++) {
          final vehicle = vehicleDuplicates[i];
          print('   Vehicle ${i + 1}: ID=${vehicle['evid']}, Registration=${vehicle['ev_registration_no']}, Type=${vehicle['ev_type']}');
        }
        print('🔧 Recommendation: Clean up duplicate vehicle entries in the database');
      }
    }
    
  } catch (e) {
    print('❌ Error checking for duplicates: $e');
  }
}

  // AVATAR UPLOAD FUNCTIONALITY
  /// Upload user avatar to Supabase Storage and update user record
  Future<bool> uploadUserAvatar(File imageFile) async {
    try {
      if (_currentUser == null) {
        print('❌ No current user found for avatar upload');
        return false;
      }

      // Delete old avatar if exists
      if (_currentUser!.avatarUrl != null) {
        await _deleteOldAvatar(_currentUser!.avatarUrl!);
      }

      // Generate unique filename using user ID and timestamp
      final String fileExt = path.extension(imageFile.path);
      final String fileName = '${_currentUser!.userId}_${DateTime.now().millisecondsSinceEpoch}$fileExt';
      
      print('🔄 Uploading avatar: $fileName');
      
      // Upload to Supabase Storage
      await _client.storage
          .from('avatars')
          .upload('users/$fileName', imageFile);

      // Get public URL
      final String publicUrl = _client.storage
          .from('avatars')
          .getPublicUrl('users/$fileName');

      print('✅ Avatar uploaded, URL: $publicUrl');

      // Update user record in database
      await _client
          .from('users')
          .update({'avatar_url': publicUrl})
          .eq('userid', _currentUser!.userId);

      // Update local user object
      _currentUser = _currentUser!.copyWith(avatarUrl: publicUrl);
      notifyListeners();

      print('✅ Avatar updated successfully for user: ${_currentUser!.name}');
      return true;
    } catch (e) {
      print('❌ Error uploading avatar: $e');
      return false;
    }
  }

  /// Delete old avatar from storage (private helper method)
  Future<void> _deleteOldAvatar(String avatarUrl) async {
    try {
      // Extract file path from URL
      final uri = Uri.parse(avatarUrl);
      final segments = uri.pathSegments;
      final bucketIndex = segments.indexOf('avatars');
      
      if (bucketIndex != -1 && bucketIndex < segments.length - 1) {
        final filePath = segments.sublist(bucketIndex + 1).join('/');
        await _client.storage.from('avatars').remove([filePath]);
        print('✅ Old avatar deleted: $filePath');
      }
    } catch (e) {
      print('❌ Error deleting old avatar: $e');
      // Don't fail the upload if we can't delete the old avatar
    }
  }

  /// Update user profile data (including avatar)
  Future<bool> updateUserProfile({
    String? name,
    String? avatarUrl,
  }) async {
    try {
      if (_currentUser == null) {
        print('❌ No current user found for profile update');
        return false;
      }

      Map<String, dynamic> updateData = {};
      
      if (name != null) updateData['name'] = name;
      if (avatarUrl != null) updateData['avatar_url'] = avatarUrl;

      if (updateData.isEmpty) {
        print('⚠️ No data to update');
        return false;
      }

      // Update database
      await _client
          .from('users')
          .update(updateData)
          .eq('userid', _currentUser!.userId);

      // Update local user object
      _currentUser = _currentUser!.copyWith(
        name: name ?? _currentUser!.name,
        avatarUrl: avatarUrl ?? _currentUser!.avatarUrl,
      );
      
      notifyListeners();
      print('✅ User profile updated successfully');
      return true;
    } catch (e) {
      print('❌ Error updating user profile: $e');
      return false;
    }
  }

  // EXISTING FUNCTIONALITY CONTINUES...

  // FIXED: Enhanced alert triggering with proper error handling
  Future<bool> triggerAlert(int billboardId, String evRegistrationNo) async {
    print('🚨 TRIGGERING ALERT - Billboard: $billboardId, Vehicle: $evRegistrationNo');
    
    try {
      // Step 1: Verify billboard exists
      final billboardExists = await _client
          .from('billboard')
          .select('billboardid')
          .eq('billboardid', billboardId)
          .maybeSingle();
      
      if (billboardExists == null) {
        print('❌ Billboard $billboardId does not exist');
        return false;
      }

      // Step 2: Verify emergency vehicle exists  
      final vehicleExists = await _client
          .from('emergencyvehicle')
          .select('ev_registration_no')
          .eq('ev_registration_no', evRegistrationNo)
          .maybeSingle();
      
      if (vehicleExists == null) {
        print('❌ Emergency vehicle $evRegistrationNo does not exist');
        return false;
      }

      final now = DateTime.now();
      final timestamp = now.toIso8601String();
      
      // Step 3: Insert into alerts table (UUID is auto-generated)
      print('🔍 Inserting into alerts table...');
      final alertsData = {
        'ev_registration_no': evRegistrationNo,
        'billboard_id': billboardId,
        'triggered_at': timestamp,
      };
      
      final alertResult = await _client
          .from('alerts')
          .insert(alertsData)
          .select('id'); // Return the generated UUID
      
      print('✅ Alert inserted successfully: ${alertResult.first['id']}');

      // Step 4: Insert into alertlog table (alertid is auto-generated)
      print('🔍 Inserting into alertlog table...');
      final alertLogData = {
        'date': timestamp.split('T')[0], // Extract date part (YYYY-MM-DD)
        'time': timestamp.split('T')[1].split('.')[0], // Extract time part (HH:MM:SS)
        'billboardid': billboardId,
        'ev_registration_no': evRegistrationNo,
        'type_of_activation': 'PROXIMITY_AUTO',
        'result': 'SUCCESS',
        'created_at': timestamp,
      };
      
      final logResult = await _client
          .from('alertlog')
          .insert(alertLogData)
          .select('alertid');
      
      print('✅ Alert log inserted successfully: ${logResult.first['alertid']}');
      print('🎉 ALERT TRIGGERED SUCCESSFULLY for Billboard $billboardId');
      
      return true;
      
    } catch (e) {
      print('❌ ERROR TRIGGERING ALERT: $e');
      
      // Enhanced error logging with more details
      if (e is PostgrestException) {
        print('❌ PostgreSQL Error:');
        print('   Code: ${e.code}');
        print('   Message: ${e.message}');
        print('   Details: ${e.details}');
        print('   Hint: ${e.hint}');
      }
      
      // Log the failed attempt to alertlog
      await _logFailedAttempt(billboardId, evRegistrationNo, 'PROXIMITY_AUTO', e.toString());
      
      return false;
    }
  }

  // FIXED: Enhanced manual activation
  Future<bool> manualActivation(int billboardId, String evRegistrationNo, bool isActivating) async {
  print('🔧 MANUAL ${isActivating ? 'ACTIVATION' : 'DEACTIVATION'} - Billboard: $billboardId');
  
  try {
    final now = DateTime.now();
    final timestamp = now.toIso8601String();
    
    // Always log the manual action first
    final alertLogData = {
      'date': timestamp.split('T')[0],
      'time': timestamp.split('T')[1].split('.')[0],
      'billboardid': billboardId,
      'ev_registration_no': evRegistrationNo,
      'type_of_activation': isActivating ? 'MANUAL_ACTIVATE' : 'MANUAL_DEACTIVATE',
      'result': 'SUCCESS',
      'created_at': timestamp,
    };
    
    await _client.from('alertlog').insert(alertLogData);
    print('✅ Manual action logged to alertlog');

    // If activating, also add to alerts table
    if (isActivating) {
      final alertsData = {
        'ev_registration_no': evRegistrationNo,
        'billboard_id': billboardId,
        'triggered_at': timestamp,
      };
      
      await _client.from('alerts').insert(alertsData);
      print('✅ Manual activation alert inserted');
    } else {
      // For deactivation, remove from alerts table
      await _client
        .from('alerts')
        .delete()
        .eq('billboard_id', billboardId)
        .eq('ev_registration_no', evRegistrationNo);
      print('✅ Manual deactivation - removed from alerts');
    }

    print('✅ Manual ${isActivating ? 'activation' : 'deactivation'} completed');
    return true;
    
  } catch (e) {
    print('❌ Error in manual activation: $e');
    await _logFailedAttempt(billboardId, evRegistrationNo, 
        isActivating ? 'MANUAL_ACTIVATE' : 'MANUAL_DEACTIVATE', e.toString());
    return false;
  }
}

  // HELPER: Log failed attempts
  Future<void> _logFailedAttempt(int billboardId, String evRegistrationNo, String actionType, String error) async {
    try {
      final now = DateTime.now();
      await _client.from('alertlog').insert({
        'date': now.toIso8601String().split('T')[0],
        'time': now.toIso8601String().split('T')[1].split('.')[0],
        'billboardid': billboardId,
        'ev_registration_no': evRegistrationNo,
        'type_of_activation': actionType,
        'result': 'FAILED: ${error.length > 100 ? error.substring(0, 100) + "..." : error}',
        'created_at': now.toIso8601String(),
      });
      print('✅ Failed attempt logged');
    } catch (logError) {
      print('❌ Could not log failed attempt: $logError');
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
          .limit(20);
      
      print('✅ Retrieved ${(response as List).length} alert logs for $evRegistrationNo');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error getting alert logs: $e');
      return [];
    }
  }

  // Get all alerts for debugging
  Future<List<Map<String, dynamic>>> getAllAlerts() async {
    try {
      final response = await _client
          .from('alerts')
          .select('*')
          .order('triggered_at', ascending: false)
          .limit(50);
      
      print('✅ Retrieved ${(response as List).length} total alerts');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching all alerts: $e');
      return [];
    }
  }

  // Get all alert logs for debugging
  Future<List<Map<String, dynamic>>> getAllAlertLogs() async {
    try {
      final response = await _client
          .from('alertlog')
          .select('*')
          .order('created_at', ascending: false)
          .limit(100);
      
      print('✅ Retrieved ${(response as List).length} total alert logs');
      return List<Map<String, dynamic>>.from(response);
    } catch (e) {
      print('❌ Error fetching alert logs: $e');
      return [];
    }
  }

  // Update billboard activation status in local state
  void updateBillboardStatus(int billboardId, bool isActivated) {
    final index = _billboards.indexWhere((b) => b.billboardId == billboardId);
    if (index != -1) {
      _billboards[index] = Billboard(
        billboardId: _billboards[index].billboardId,
        billboardNumber: _billboards[index].billboardNumber,
        location: _billboards[index].location,
        latitude: _billboards[index].latitude,
        longitude: _billboards[index].longitude,
        createdAt: _billboards[index].createdAt,
        isActivated: isActivated,
      );
      notifyListeners();
      print('✅ Billboard $billboardId status updated to: $isActivated');
    }
}

  // Get billboard by ID
  Billboard? getBillboardById(int billboardId) {
    try {
      return _billboards.firstWhere((b) => b.billboardId == billboardId);
    } catch (e) {
      print('❌ Billboard $billboardId not found in local cache');
      return null;
    }
  }

  // Get current emergency vehicle registration number
  String getCurrentEvRegistration() {
    if (_currentVehicle?.evRegistrationNo != null) {
      return _currentVehicle!.evRegistrationNo;
    } else if (_currentUser?.evRegistrationNo != null) {
      return _currentUser!.evRegistrationNo;
    } else {
      // Fallback to current user email
      final currentUser = Supabase.instance.client.auth.currentUser;
      final fallback = currentUser?.email ?? 'UNKNOWN_VEHICLE';
      print('⚠️ Using fallback EV registration: $fallback');
      return fallback;
    }
  }

  // Test database connection and tables
  Future<bool> testConnection() async {
    print('🔍 Testing database connection...');
    try {
      // Test each table
      await _client.from('billboard').select('count').limit(1);
      print('✅ Billboard table accessible');
      
      await _client.from('alerts').select('count').limit(1);
      print('✅ Alerts table accessible');
      
      await _client.from('alertlog').select('count').limit(1);
      print('✅ AlertLog table accessible');
      
      await _client.from('emergencyvehicle').select('count').limit(1);
      print('✅ EmergencyVehicle table accessible');
      
      print('🎉 All database tables accessible');
      return true;
    } catch (e) {
      print('❌ Database connection test failed: $e');
      return false;
    }
  }

  // DEBUGGING: Test alert insertion with sample data
  Future<void> debugTestAlert() async {
    print('🧪 TESTING ALERT INSERTION...');
    
    try {
      // Get first billboard for testing
      final billboards = await _client.from('billboard').select('*').limit(1);
      if (billboards.isEmpty) {
        print('❌ No billboards found for testing');
        return;
      }
      
      final testBillboardId = billboards.first['billboardid'];
      print('🔍 Using test billboard ID: $testBillboardId');
      
      // Get first emergency vehicle for testing
      final vehicles = await _client.from('emergencyvehicle').select('*').limit(1);
      if (vehicles.isEmpty) {
        print('❌ No emergency vehicles found for testing');
        return;
      }
      
      final testEvRegistration = vehicles.first['ev_registration_no'];
      print('🔍 Using test EV registration: $testEvRegistration');
      
      // Test the triggerAlert function
      final success = await triggerAlert(testBillboardId, testEvRegistration);
      
      if (success) {
        print('🎉 TEST ALERT SUCCESSFUL!');
        
        // Check if data was actually inserted
        final alertCount = await _client.from('alerts').select('count').count();
        final logCount = await _client.from('alertlog').select('count').count();
        
        print('📊 Current alerts count: ${alertCount.count}');
        print('📊 Current alertlog count: ${logCount.count}');
      } else {
        print('❌ TEST ALERT FAILED!');
      }
      
    } catch (e) {
      print('❌ Debug test error: $e');
    }
  }
Future<void> cleanupExpiredAlerts({int expirationMinutes = 15}) async {
  try {
    print('🧹 Cleaning up expired alerts (older than $expirationMinutes minutes)...');
    
    final expiredTime = DateTime.now()
        .subtract(Duration(minutes: expirationMinutes))
        .toIso8601String();
    
    // Get expired alerts for logging
    final expiredAlerts = await _client
        .from('alerts')
        .select('*')
        .lt('triggered_at', expiredTime);
    
    if (expiredAlerts.isNotEmpty) {
      print('🔍 Found ${expiredAlerts.length} expired alerts to clean up');
      
      // Log each expired alert as AUTO_EXPIRED
      for (var alert in expiredAlerts) {
        await _logFailedAttempt(
          alert['billboard_id'], 
          alert['ev_registration_no'], 
          'AUTO_EXPIRED', 
          'Alert expired after $expirationMinutes minutes'
        );
      }
      
      // Delete expired alerts
      await _client
          .from('alerts')
          .delete()
          .lt('triggered_at', expiredTime);
      
      print('✅ Cleaned up ${expiredAlerts.length} expired alerts');
    } else {
      print('✅ No expired alerts found');
    }
    
  } catch (e) {
    print('❌ Error cleaning up expired alerts: $e');
  }
}

Future<void> cleanupUserAlerts(String evRegistrationNo) async {
  try {
    print('🧹 Cleaning up old alerts for vehicle: $evRegistrationNo');
    
    // Get existing alerts for this vehicle
    final existingAlerts = await _client
        .from('alerts')
        .select('*')
        .eq('ev_registration_no', evRegistrationNo);
    
    if (existingAlerts.isNotEmpty) {
      print('🔍 Found ${existingAlerts.length} existing alerts for $evRegistrationNo');
      
      // Log each as cleaned up
      for (var alert in existingAlerts) {
        await _client.from('alertlog').insert({
          'date': DateTime.now().toIso8601String().split('T')[0],
          'time': DateTime.now().toIso8601String().split('T')[1].split('.')[0],
          'billboardid': alert['billboard_id'],
          'ev_registration_no': evRegistrationNo,
          'type_of_activation': 'AUTO_CLEANUP',
          'result': 'User logged in - cleaning old alerts',
          'created_at': DateTime.now().toIso8601String(),
        });
      }
      
      // Remove all existing alerts for this vehicle
      await _client
          .from('alerts')
          .delete()
          .eq('ev_registration_no', evRegistrationNo);
      
      print('✅ Cleaned up ${existingAlerts.length} old alerts for $evRegistrationNo');
    }
    
  } catch (e) {
    print('❌ Error cleaning up user alerts: $e');
  }
}

  @override
Future<void> signOut() async {
  try {
    print('🔄 Signing out user...');
    
    // Clean up any active alerts for this user before signing out
    final evRegistration = getCurrentEvRegistration();
    if (evRegistration != 'UNKNOWN_VEHICLE') {
      await cleanupUserAlerts(evRegistration);
    }
    
    // Sign out from Supabase Auth
    await _client.auth.signOut();
    
    // Clear all cached user data
    _currentUser = null;
    _currentVehicle = null;
    _billboards = [];
    
    // Notify all listeners about the state change
    notifyListeners();
    
    print('✅ User signed out successfully with cleanup');
  } catch (e) {
    print('❌ Error signing out: $e');
    rethrow;
  }
}

  /// Signs out the current user from all devices
  Future<void> signOutFromAllDevices() async {
    try {
      print('🔄 Signing out user from all devices...');
      
      // Sign out from all devices
      await _client.auth.signOut(scope: SignOutScope.global);
      
      // Clear all cached user data
      _currentUser = null;
      _currentVehicle = null;
      _billboards = [];
      
      // Notify all listeners about the state change
      notifyListeners();
      
      print('✅ User signed out from all devices successfully');
    } catch (e) {
      print('❌ Error signing out from all devices: $e');
      rethrow;
    }
  }

  /// Check if user is currently signed in
  bool get isSignedIn {
    return _client.auth.currentUser != null;
  }

  /// Get current authenticated user's email
  String? get currentUserEmail {
    return _client.auth.currentUser?.email;
  }

  // Get statistics
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

      final logCount = await _client
          .from('alertlog')
          .select('count')
          .count(CountOption.exact);

      final stats = {
        'billboards': billboardCount.count,
        'alerts': alertCount.count,
        'vehicles': vehicleCount.count,
        'logs': logCount.count,
      };
      
      print('📊 Database Statistics: $stats');
      return stats;
    } catch (e) {
      print('❌ Error getting statistics: $e');
      return {
        'billboards': 0,
        'alerts': 0,
        'vehicles': 0,
        'logs': 0,
      };
    }
  }
}



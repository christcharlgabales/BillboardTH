//driver main_screen.dart

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../services/location_service.dart';
import '../services/supabase_service.dart';
import '../services/auth_service.dart';
import 'package:geolocator/geolocator.dart';
import '../models/billboard.dart';
import 'profile_screen.dart';
import 'ev_info_screen.dart';
import 'login_screen.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1;
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Billboard? _selectedBillboard;
  bool _isDialogOpen = false;
  
  // Track active billboards (those currently triggered by proximity)
  Set<int> _activeBillboards = {};
  bool _isLocationListenerSet = false;
  
  // Performance optimization variables
  Timer? _cameraUpdateTimer;
  Timer? _markerUpdateTimer;
  Position? _lastCameraPosition;
  List<Billboard>? _lastBillboardsState;
  static const double _cameraUpdateThreshold = 0.001; // ~100m threshold
  static const Duration _cameraUpdateDelay = Duration(milliseconds: 500);
  static const Duration _markerUpdateDelay = Duration(milliseconds: 300);
  
  // Billboard alert constants
  static const double BILLBOARD_RADIUS = 500.0; 

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  void _initializeScreen() async {
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadInitialData();
      _setupLocationListener();
    });
  }

  Future<void> _loadInitialData() async {
    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      
      // Test database connection first
      final connectionOk = await supabaseService.testConnection();
      if (!connectionOk) {
        _showError('Database connection failed. Please check your internet connection.');
        return;
      }
      
      if (supabaseService.billboards.isEmpty) {
        await supabaseService.loadBillboards();
      }

      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser?.email != null) {
        await supabaseService.loadUserData(currentUser!.email!);
        
        // Debug: Check if we have a valid emergency vehicle
        final evRegistration = supabaseService.getCurrentEvRegistration();
        if (evRegistration == 'UNKNOWN_VEHICLE') {
          print('⚠️ Warning: No emergency vehicle registration found');
          _showError('No emergency vehicle registration found. Please contact support.');
        } else {
          print('✅ Using EV registration: $evRegistration');
        }
      }
    } catch (e) {
      print('❌ Error in initial data loading: $e');
      _showError('Error loading initial data: ${e.toString()}');
    }
  }

  void _showError(String message) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: Color(0xFFD32F2F),
          duration: Duration(seconds: 5),
        ),
      );
    }
  }

  void _setupLocationListener() {
    if (_isLocationListenerSet) return;
    
    final locationService = Provider.of<LocationService>(context, listen: false);
    locationService.addListener(_onLocationUpdate);
    _isLocationListenerSet = true;
  }

  void _onLocationUpdate() {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    
    if (locationService.currentPosition != null && locationService.isTracking) {
      _debouncedCameraUpdate(locationService);
      _checkBillboardProximity(locationService.currentPosition!, supabaseService);
    }
  }

  void _checkBillboardProximity(Position userPosition, SupabaseService supabaseService) {
    if (!mounted) return;
    
    final evRegistration = supabaseService.getCurrentEvRegistration();
    
    // Don't check proximity if no valid registration
    if (evRegistration == 'UNKNOWN_VEHICLE') {
      print('⚠️ Skipping proximity check - no valid EV registration');
      return;
    }
    
    for (Billboard billboard in supabaseService.billboards) {
      double distance = Geolocator.distanceBetween(
        userPosition.latitude, 
        userPosition.longitude,
        billboard.latitude, 
        billboard.longitude
      );

      bool isWithinRadius = distance <= BILLBOARD_RADIUS;
      bool wasActive = _activeBillboards.contains(billboard.billboardId);

      if (isWithinRadius && !wasActive) {
        _activateBillboard(billboard, supabaseService, evRegistration);
      } else if (!isWithinRadius && wasActive) {
        _deactivateBillboard(billboard, supabaseService, evRegistration);
      }
    }
  }

  void _activateBillboard(Billboard billboard, SupabaseService supabaseService, String evRegistration) async {
    if (!mounted) return;
    
    _activeBillboards.add(billboard.billboardId);
    supabaseService.updateBillboardStatus(billboard.billboardId, true);
    
    // Trigger alert with error handling
    try {
      final success = await supabaseService.triggerAlert(billboard.billboardId, evRegistration);
      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("🚨 EMERGENCY ALERT: Billboard ${billboard.billboardNumber} activated!"),
            backgroundColor: Color(0xFFD32F2F),
            duration: Duration(seconds: 3),
          ),
        );
        print('✅ Billboard ${billboard.billboardNumber} ACTIVATED (proximity)');
      } else {
        print('❌ Failed to trigger alert for Billboard ${billboard.billboardNumber}');
        _activeBillboards.remove(billboard.billboardId);
        supabaseService.updateBillboardStatus(billboard.billboardId, false);
      }
    } catch (e) {
      print('❌ Error activating billboard: $e');
      _activeBillboards.remove(billboard.billboardId);
      supabaseService.updateBillboardStatus(billboard.billboardId, false);
    }
  }

  void _deactivateBillboard(Billboard billboard, SupabaseService supabaseService, String evRegistration) async {
    if (!mounted) return;
    
    _activeBillboards.remove(billboard.billboardId);
    supabaseService.updateBillboardStatus(billboard.billboardId, false);
    
    try {
      await supabaseService.manualActivation(billboard.billboardId, evRegistration, false);
      
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("✅ Billboard ${billboard.billboardNumber} deactivated (out of range)"),
          backgroundColor: Color(0xFF388E3C),
          duration: Duration(seconds: 2),
        ),
      );
      
      print('✅ Billboard ${billboard.billboardNumber} DEACTIVATED (out of range)');
    } catch (e) {
      print('❌ Error deactivating billboard: $e');
    }
  }

  void _stopAllBillboardAlerts() async {
    if (!mounted) return;
    
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final evRegistration = supabaseService.getCurrentEvRegistration();
    
    if (evRegistration == 'UNKNOWN_VEHICLE') {
      _activeBillboards.clear();
      return;
    }
    
    final List<int> billboardsToStop = List.from(_activeBillboards);
    
    for (int billboardId in billboardsToStop) {
      final billboard = supabaseService.getBillboardById(billboardId);
      if (billboard != null) {
        try {
          supabaseService.updateBillboardStatus(billboardId, false);
          await supabaseService.manualActivation(billboardId, evRegistration, false);
        } catch (e) {
          print('❌ Error stopping billboard $billboardId: $e');
        }
      }
    }
    
    final hadActiveBillboards = _activeBillboards.isNotEmpty;
    _activeBillboards.clear();
    
    if (hadActiveBillboards) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🔴 All billboard alerts stopped"),
          backgroundColor: Colors.grey[600],
          duration: Duration(seconds: 2),
        ),
      );
    }
    
    print('🔴 All billboard alerts stopped due to tracking stop');
  }

  void _debouncedCameraUpdate(LocationService locationService) {
    final currentPos = locationService.currentPosition!;
    
    if (_lastCameraPosition != null) {
      double distance = Geolocator.distanceBetween(
        _lastCameraPosition!.latitude,
        _lastCameraPosition!.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );
      
      if (distance < 100) return; // 100 meters
    }
    
    _cameraUpdateTimer?.cancel();
    _cameraUpdateTimer = Timer(_cameraUpdateDelay, () {
      if (_mapController != null && mounted) {
        _mapController?.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(
              target: LatLng(currentPos.latitude, currentPos.longitude),
              zoom: 15,
            ),
          ),
        );
        _lastCameraPosition = currentPos;
      }
    });
  }

  @override
  void dispose() {
    _cameraUpdateTimer?.cancel();
    _markerUpdateTimer?.cancel();
    
    if (_isLocationListenerSet) {
      final locationService = Provider.of<LocationService>(context, listen: false);
      locationService.removeListener(_onLocationUpdate);
    }
    
    super.dispose();
  }

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  Widget _buildBody() {
    switch (_selectedIndex) {
      case 0:
        return ProfileScreen();
      case 1:
        return _buildAlertScreen();
      case 2:
        return EVInfoScreen();
      default:
        return _buildAlertScreen();
    }
  }

  Widget _buildAlertScreen() {
    return Consumer2<LocationService, SupabaseService>(
      builder: (context, locationService, supabaseService, child) {
        _debouncedMarkerUpdate(supabaseService.billboards);

        return Column(
          children: [
            _buildEmergencyHeader(supabaseService),
            _buildCompactLocationStatus(locationService, supabaseService),
            Expanded(
              child: _buildMapContainer(locationService, supabaseService),
            ),
            _buildEmergencyControlPanel(locationService, supabaseService),
          ],
        );
      },
    );
  }

  void _debouncedMarkerUpdate(List<Billboard> billboards) {
    if (_lastBillboardsState != null && _billboardsEqual(_lastBillboardsState!, billboards)) {
      return;
    }
    
    _markerUpdateTimer?.cancel();
    _markerUpdateTimer = Timer(_markerUpdateDelay, () {
      if (mounted) {
        _updateMarkers(billboards);
        _lastBillboardsState = List.from(billboards);
      }
    });
  }

  bool _billboardsEqual(List<Billboard> list1, List<Billboard> list2) {
    if (list1.length != list2.length) return false;
    
    for (int i = 0; i < list1.length; i++) {
      if (list1[i].billboardId != list2[i].billboardId ||
          list1[i].isActivated != list2[i].isActivated) {
        return false;
      }
    }
    return true;
  }

  Widget _buildEmergencyHeader(SupabaseService supabaseService) {
    final evRegistration = supabaseService.getCurrentEvRegistration();
    final isValidRegistration = evRegistration != 'UNKNOWN_VEHICLE';
    
    return Container(
      width: double.infinity,
      padding: EdgeInsets.all(12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF8B4B3B), Color(0xFF6D3829)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
            color: Color(0xFF8B4B3B).withOpacity(0.3),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(
                  Icons.emergency,
                  color: Color(0xFF8B4B3B),
                  size: 18,
                ),
              ),
              SizedBox(width: 12),
              Expanded(
                child: Text(
                  'EMERGENCY ALERT SYSTEM',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
              Container(
                padding: EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: IconButton(
                  icon: Icon(Icons.logout, color: Colors.white, size: 16),
                  onPressed: _logout,
                  constraints: BoxConstraints(minWidth: 24, minHeight: 24),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
          if (!isValidRegistration)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              margin: EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Color(0xFFFF9800).withOpacity(0.2),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: Color(0xFFFF9800)),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Color(0xFFFF9800), size: 12),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'No EV registration found. Contact support.',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  void _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signOut();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
    }
  }

  Widget _buildCompactLocationStatus(LocationService locationService, SupabaseService supabaseService) {
    final evRegistration = supabaseService.getCurrentEvRegistration();
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey[300]!, width: 1),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: locationService.isTracking 
                  ? Color(0xFF388E3C).withOpacity(0.1) 
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(4),
            ),
            child: Icon(
              locationService.isTracking ? Icons.gps_fixed : Icons.gps_off,
              color: locationService.isTracking ? Color(0xFF388E3C) : Colors.grey,
              size: 14,
            ),
          ),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              locationService.currentPosition != null
                  ? 'GPS: ${locationService.currentPosition!.latitude.toStringAsFixed(3)}, ${locationService.currentPosition!.longitude.toStringAsFixed(3)}'
                  : 'No GPS signal',
              style: TextStyle(fontSize: 10, color: Colors.grey[700]),
            ),
          ),
          if (_activeBillboards.isNotEmpty)
            Container(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: Color(0xFFD32F2F),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${_activeBillboards.length} ACTIVE',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 8,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          if (evRegistration != 'UNKNOWN_VEHICLE')
            Padding(
              padding: EdgeInsets.only(left: 8),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: Color(0xFF8B4B3B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  'EV: $evRegistration',
                  style: TextStyle(
                    fontSize: 8,
                    color: Color(0xFF8B4B3B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapContainer(LocationService locationService, SupabaseService supabaseService) {
    return Container(
      margin: EdgeInsets.all(8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Color(0xFF8B4B3B).withOpacity(0.3), width: 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 4,
            offset: Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: GoogleMap(
          onMapCreated: (GoogleMapController controller) {
            _mapController = controller;
            if (supabaseService.billboards.isNotEmpty) {
              _updateMarkers(supabaseService.billboards);
            }
          },
          initialCameraPosition: CameraPosition(
            target: locationService.currentPosition != null
                ? LatLng(locationService.currentPosition!.latitude, locationService.currentPosition!.longitude)
                : LatLng(8.9475, 125.5406), // Butuan coordinates as fallback
            zoom: 13,
          ),
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: false,
          onTap: _onMapTap,
          liteModeEnabled: false,
          mapToolbarEnabled: false,
          zoomControlsEnabled: false,
          compassEnabled: false,
        ),
      ),
    );
  }

  void _onMapTap(LatLng position) {
    if (_selectedBillboard != null) {
      setState(() {
        _selectedBillboard = null;
      });
    }
    if (_isDialogOpen) {
      _dismissDialog();
    }
  }

  Widget _buildEmergencyControlPanel(LocationService locationService, SupabaseService supabaseService) {
  final evRegistration = supabaseService.getCurrentEvRegistration();
  final isValidRegistration = evRegistration != 'UNKNOWN_VEHICLE';
  
  return Container(
    padding: EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.white,
      border: Border(
        top: BorderSide(color: Colors.grey[300]!, width: 1),
      ),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: double.infinity,
          height: 48,
          child: ElevatedButton(
            onPressed: isValidRegistration ? () => _handleTrackingButton(locationService) : null,
            style: ElevatedButton.styleFrom(
              backgroundColor: isValidRegistration 
                  ? (locationService.isTracking ? Color(0xFFD32F2F) : Color(0xFF8B4B3B))
                  : Colors.grey[400],
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              elevation: isValidRegistration ? 4 : 0,
              // Add padding to prevent overflow
              padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              mainAxisSize: MainAxisSize.min, // This prevents the row from taking full width
              children: [
                Container(
                  padding: EdgeInsets.all(4),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Icon(
                    locationService.isTracking ? Icons.stop : Icons.play_arrow,
                    size: 16, // Reduced from 18 to 16
                  ),
                ),
                SizedBox(width: 6), // Reduced from 8 to 6
                Flexible( // Wrap text in Flexible to prevent overflow
                  child: Text(
                    locationService.isTracking ? 'STOP EMERGENCY ALERT' : 'START EMERGENCY ALERT',
                    style: TextStyle(
                      fontSize: 13, // Reduced from 14 to 13
                      fontWeight: FontWeight.bold,
                    ),
                    overflow: TextOverflow.ellipsis, // Handle text overflow
                    maxLines: 1,
                  ),
                ),
              ],
            ),
          ),
        ),
        SizedBox(height: 6),
        if (!isValidRegistration)
          Text(
            'Cannot start tracking without valid EV registration',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFFD32F2F),
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
          )
        else if (locationService.statusMessage.isNotEmpty)
          Text(
            locationService.statusMessage,
            style: TextStyle(
              fontSize: 10,
              color: Colors.grey[600],
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
          ),
      ],
    ),
  );
}

  void _handleTrackingButton(LocationService locationService) {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final evRegistration = supabaseService.getCurrentEvRegistration();
    
    if (evRegistration == 'UNKNOWN_VEHICLE') {
      _showError('Cannot start tracking without valid emergency vehicle registration');
      return;
    }
    
    if (locationService.isTracking) {
      _stopAllBillboardAlerts();
      locationService.stopTracking();
    } else {
      locationService.startTracking();
    }
  }

  void _updateMarkers(List<Billboard> billboards) {
    if (!mounted) return;
    
    setState(() {
      _markers = billboards.map((billboard) {
        return Marker(
          markerId: MarkerId(billboard.billboardId.toString()),
          position: LatLng(billboard.latitude, billboard.longitude),
          onTap: () => _onMarkerTap(billboard),
          icon: BitmapDescriptor.defaultMarkerWithHue(
            billboard.isActivated ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
          infoWindow: InfoWindow(
            title: 'Billboard ${billboard.billboardNumber}',
            snippet: '${billboard.location}\n${billboard.isActivated ? "ACTIVE" : "INACTIVE"}',
          ),
        );
      }).toSet();
    });
  }

  void _onMarkerTap(Billboard billboard) {
    setState(() {
      _selectedBillboard = billboard;
    });
    _toggleDialog(billboard);
  }

  void _toggleDialog(Billboard billboard) {
    if (_isDialogOpen) {
      _dismissDialog();
    } else {
      _showDialog(billboard);
    }
  }

  void _showDialog(Billboard billboard) {
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final evRegistration = supabaseService.getCurrentEvRegistration();
    
    if (evRegistration == 'UNKNOWN_VEHICLE') {
      _showError('Cannot control billboard without valid emergency vehicle registration');
      return;
    }
    
    setState(() {
      _isDialogOpen = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Row(
            children: [
              Container(
                padding: EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: Color(0xFF8B4B3B),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.control_point, color: Colors.white, size: 16),
              ),
              SizedBox(width: 8),
              Text(
                'Billboard Control',
                style: TextStyle(
                  color: Color(0xFF8B4B3B),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Color(0xFF8B4B3B).withOpacity(0.1),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Billboard: ${billboard.billboardNumber}', 
                         style: TextStyle(fontWeight: FontWeight.w600, fontSize: 12)),
                    Text('Location: ${billboard.location}', 
                         style: TextStyle(fontSize: 11, color: Colors.grey[700])),
                  ],
                ),
              ),
              SizedBox(height: 12),
              Text(
                billboard.isActivated
                    ? 'Do you want to manually deactivate this billboard?'
                    : 'Do you want to manually activate this billboard?',
                style: TextStyle(fontSize: 12),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _manualToggleBillboard(billboard);
                _dismissDialog();
              },
              style: TextButton.styleFrom(
                backgroundColor: billboard.isActivated ? Color(0xFFFF9800) : Color(0xFF8B4B3B),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              child: Text(
                billboard.isActivated ? 'DEACTIVATE' : 'ACTIVATE',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _dismissDialog();
              },
              child: Text(
                'Cancel',
                style: TextStyle(color: Colors.grey[600], fontSize: 11),
              ),
            ),
          ],
        );
      },
    ).then((_) {
      _dismissDialog();
    });
  }

  void _dismissDialog() {
    if (mounted) {
      setState(() {
        _isDialogOpen = false;
      });
    }
  }

  void _manualToggleBillboard(Billboard billboard) async {
    if (!mounted) return;
    
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final evRegistration = supabaseService.getCurrentEvRegistration();
    final newState = !billboard.isActivated;
    
    try {
      // Update local state first
      supabaseService.updateBillboardStatus(billboard.billboardId, newState);
      
      // Attempt manual activation/deactivation
      final success = await supabaseService.manualActivation(
        billboard.billboardId, 
        evRegistration, 
        newState
      );
      
      if (success) {
        setState(() {
          if (newState) {
            _activeBillboards.add(billboard.billboardId);
          } else {
            _activeBillboards.remove(billboard.billboardId);
          }
        });

        // Show feedback to user
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              newState
                  ? "✅ Billboard ${billboard.billboardNumber} manually activated!"
                  : "✅ Billboard ${billboard.billboardNumber} manually deactivated!",
            ),
            backgroundColor: newState ? Color(0xFF388E3C) : Color(0xFF1976D2),
            duration: Duration(seconds: 2),
          ),
        );
        
        print('🔧 Billboard ${billboard.billboardNumber} manually ${newState ? 'activated' : 'deactivated'}');
        
        // Force update markers
        _updateMarkers(supabaseService.billboards);
        
      } else {
        // Revert local state if operation failed
        supabaseService.updateBillboardStatus(billboard.billboardId, !newState);
        _showError('Failed to ${newState ? 'activate' : 'deactivate'} billboard. Please try again.');
      }
  } catch (e) {
    print('❌ Error in manual toggle: $e');
    // Revert the local state
    supabaseService.updateBillboardStatus(billboard.billboardId, !newState);
    _showError('Error controlling billboard: ${e.toString()}');
  }
}

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(child: _buildBody()),
      bottomNavigationBar: BottomNavigationBar(
        items: [
          BottomNavigationBarItem(
            icon: Icon(Icons.person),
            label: 'Profile',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.warning),
            label: 'Alert',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.local_shipping),
            label: 'EV Info',
          ),
        ],
        currentIndex: _selectedIndex,
        selectedItemColor: Color(0xFF8B4B3B),
        onTap: _onItemTapped,
      ),
    );
  }
}
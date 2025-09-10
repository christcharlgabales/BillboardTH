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
          backgroundColor: Colors.red,
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
            backgroundColor: Colors.red,
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
          backgroundColor: Colors.green,
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
          backgroundColor: Colors.grey,
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
            _buildHeader(supabaseService),
            _buildLocationStatus(locationService, supabaseService),
            Expanded(
              child: _buildMapContainer(locationService, supabaseService),
            ),
            _buildControlPanel(locationService, supabaseService),
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

  Widget _buildHeader(SupabaseService supabaseService) {
    final evRegistration = supabaseService.getCurrentEvRegistration();
    final isValidRegistration = evRegistration != 'UNKNOWN_VEHICLE';
    
    return Container(
      padding: EdgeInsets.all(16),
      child: Column(
        children: [
          Row(
            children: [
              Icon(Icons.navigation, size: 24),
              SizedBox(width: 8),
              Text('ALERT TO DIVERT', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              Spacer(),
              IconButton(
                icon: Icon(Icons.logout),
                onPressed: _logout,
              ),
            ],
          ),
          if (!isValidRegistration)
            Container(
              width: double.infinity,
              padding: EdgeInsets.all(8),
              margin: EdgeInsets.only(top: 8),
              decoration: BoxDecoration(
                color: Colors.orange.shade100,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning, color: Colors.orange, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'No emergency vehicle registration found. Contact support.',
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade800),
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

  Widget _buildLocationStatus(LocationService locationService, SupabaseService supabaseService) {
    final evRegistration = supabaseService.getCurrentEvRegistration();
    
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          Row(
            children: [
              Icon(
                locationService.isTracking ? Icons.gps_fixed : Icons.gps_off,
                color: locationService.isTracking ? Colors.green : Colors.grey,
              ),
              SizedBox(width: 8),
              Expanded(
                child: Text(
                  locationService.currentPosition != null
                      ? 'Lat: ${locationService.currentPosition!.latitude.toStringAsFixed(4)}, Lng: ${locationService.currentPosition!.longitude.toStringAsFixed(4)}'
                      : 'No location data',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (_activeBillboards.isNotEmpty)
                Container(
                  padding: EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_activeBillboards.length} Active',
                    style: TextStyle(color: Colors.white, fontSize: 10),
                  ),
                ),
            ],
          ),
          if (evRegistration != 'UNKNOWN_VEHICLE')
            Padding(
              padding: EdgeInsets.only(top: 4),
              child: Row(
                children: [
                  Icon(Icons.local_shipping, size: 16, color: Colors.blue),
                  SizedBox(width: 8),
                  Text(
                    'EV: $evRegistration',
                    style: TextStyle(fontSize: 11, color: Colors.blue),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMapContainer(LocationService locationService, SupabaseService supabaseService) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
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
          myLocationButtonEnabled: true,
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

  Widget _buildControlPanel(LocationService locationService, SupabaseService supabaseService) {
    final evRegistration = supabaseService.getCurrentEvRegistration();
    final isValidRegistration = evRegistration != 'UNKNOWN_VEHICLE';
    
    return Container(
      height: 140,
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            height: 50,
            child: ElevatedButton(
              onPressed: isValidRegistration ? () => _handleTrackingButton(locationService) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: isValidRegistration ? Color(0xFF8B4B3B) : Colors.grey,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(25),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    locationService.isTracking ? 'STOP' : 'START',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                  SizedBox(width: 8),
                  Icon(
                    locationService.isTracking ? Icons.stop : Icons.play_arrow,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 8),
          if (!isValidRegistration)
            Text(
              'Cannot start tracking without valid EV registration',
              style: TextStyle(fontSize: 11, color: Colors.red),
              textAlign: TextAlign.center,
            )
          else if (locationService.statusMessage.isNotEmpty)
            Flexible(
              child: Text(
                locationService.statusMessage,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
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

  bool _markersEqual(Set<Marker> set1, Set<Marker> set2) {
    if (set1.length != set2.length) return false;
    
    for (Marker marker1 in set1) {
      bool found = false;
      for (Marker marker2 in set2) {
        if (marker1.markerId == marker2.markerId && 
            marker1.position == marker2.position) {
          found = true;
          break;
        }
      }
      if (!found) return false;
    }
    return true;
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
          title: Text('Billboard Control'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Billboard: ${billboard.billboardNumber}'),
              Text('Location: ${billboard.location}'),
              SizedBox(height: 8),
              Text(
                billboard.isActivated
                    ? 'Do you want to manually deactivate this billboard?'
                    : 'Do you want to manually activate this billboard?'
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
              child: Text(billboard.isActivated ? 'DEACTIVATE' : 'ACTIVATE'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _dismissDialog();
              },
              child: Text('Cancel'),
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
          backgroundColor: newState ? Colors.green : Colors.blue,
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
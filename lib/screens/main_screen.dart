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
  Set<int> _triggeredBillboards = {};
  bool _isLocationListenerSet = false;
  
  // Performance optimization variables
  Timer? _cameraUpdateTimer;
  Timer? _markerUpdateTimer;
  Position? _lastCameraPosition;
  List<Billboard>? _lastBillboardsState;
  static const double _cameraUpdateThreshold = 0.001; // ~100m threshold
  static const Duration _cameraUpdateDelay = Duration(milliseconds: 500);
  static const Duration _markerUpdateDelay = Duration(milliseconds: 300);

  @override
  void initState() {
    super.initState();
    _initializeScreen();
  }

  // Separate initialization to avoid blocking the main thread
  void _initializeScreen() async {
    // Use addPostFrameCallback for non-blocking initialization
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _loadInitialData();
      _setupLocationListener();
    });
  }

  // Async data loading to prevent blocking
  Future<void> _loadInitialData() async {
    try {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      
      // Load billboards only if empty
      if (supabaseService.billboards.isEmpty) {
        await supabaseService.loadBillboards();
      }

      // Load user data asynchronously
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser?.email != null) {
        // Don't await this to prevent blocking
        supabaseService.loadUserData(currentUser!.email!).catchError((error) {
          print('Error loading user data: $error');
          // Handle the type mismatch error silently
        });
      }
    } catch (e) {
      print('Error in initial data loading: $e');
    }
  }

  void _setupLocationListener() {
    if (_isLocationListenerSet) return;
    
    final locationService = Provider.of<LocationService>(context, listen: false);
    locationService.addListener(_onLocationUpdate);
    _isLocationListenerSet = true;
  }

  // Debounced location update to prevent excessive camera updates
  void _onLocationUpdate() {
    final locationService = Provider.of<LocationService>(context, listen: false);
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    
    if (locationService.currentPosition != null && locationService.isTracking) {
      _debouncedCameraUpdate(locationService);
      _checkProximityThrottled(locationService.currentPosition!, supabaseService.billboards);
    }
  }

  // Debounced camera update to reduce excessive map animations
  void _debouncedCameraUpdate(LocationService locationService) {
    final currentPos = locationService.currentPosition!;
    
    // Check if camera update is needed (significant position change)
    if (_lastCameraPosition != null) {
      double distance = Geolocator.distanceBetween(
        _lastCameraPosition!.latitude,
        _lastCameraPosition!.longitude,
        currentPos.latitude,
        currentPos.longitude,
      );
      
      // Only update if moved more than threshold
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
    // Clean up timers and listeners
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
        // Debounced marker updates
        _debouncedMarkerUpdate(supabaseService.billboards);

        return Column(
          children: [
            _buildHeader(),
            _buildLocationStatus(locationService),
            Expanded(
              child: _buildMapContainer(locationService, supabaseService),
            ),
            _buildControlPanel(locationService),
          ],
        );
      },
    );
  }

  // Debounced marker update to prevent excessive rebuilds
  void _debouncedMarkerUpdate(List<Billboard> billboards) {
    // Check if billboards actually changed
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

  // Helper method to compare billboard states
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

  Widget _buildHeader() {
    return Container(
      padding: EdgeInsets.all(16),
      child: Row(
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
    );
  }

  void _logout() async {
    final authService = Provider.of<AuthService>(context, listen: false);
    await authService.signOut();
    if (mounted) {
      Navigator.pushReplacement(context, MaterialPageRoute(builder: (context) => LoginScreen()));
    }
  }

  Widget _buildLocationStatus(LocationService locationService) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
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
            // Initial marker load
            if (supabaseService.billboards.isNotEmpty) {
              _updateMarkers(supabaseService.billboards);
            }
          },
          initialCameraPosition: CameraPosition(
            target: locationService.currentPosition != null
                ? LatLng(locationService.currentPosition!.latitude, locationService.currentPosition!.longitude)
                : LatLng(6.9214, 122.0790),
            zoom: 13,
          ),
          markers: _markers,
          myLocationEnabled: true,
          myLocationButtonEnabled: true,
          onTap: _onMapTap,
          // Performance optimizations
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

  Widget _buildControlPanel(LocationService locationService) {
    return Container(
      height: 120, // Fixed height to prevent overflow
      padding: EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: double.infinity,
            height: 50, // Reduced height
            child: ElevatedButton(
              onPressed: locationService.isTracking ? locationService.stopTracking : locationService.startTracking,
              style: ElevatedButton.styleFrom(
                backgroundColor: Color(0xFF8B4B3B),
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
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold), // Reduced font size
                  ),
                  SizedBox(width: 8),
                  Icon(
                    locationService.isTracking ? Icons.stop : Icons.play_arrow,
                    size: 20, // Reduced icon size
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 8),
          if (locationService.statusMessage.isNotEmpty)
            Flexible(
              child: Text(
                locationService.statusMessage,
                style: TextStyle(fontSize: 11, color: Colors.grey.shade600), // Reduced font size
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
              ),
            ),
        ],
      ),
    );
  }

  // Optimized marker update - only update when necessary
  void _updateMarkers(List<Billboard> billboards) {
    if (!mounted) return;
    
    final newMarkers = billboards.map((billboard) {
      return Marker(
        markerId: MarkerId(billboard.billboardId.toString()),
        position: LatLng(billboard.latitude, billboard.longitude),
        onTap: () => _onMarkerTap(billboard),
        icon: BitmapDescriptor.defaultMarkerWithHue(
          billboard.isActivated ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
        ),
      );
    }).toSet();
    
    // Only update if markers actually changed
    if (!_markersEqual(_markers, newMarkers)) {
      setState(() {
        _markers = newMarkers;
      });
    }
  }

  void _onMarkerTap(Billboard billboard) {
    setState(() {
      _selectedBillboard = billboard;
    });
    _toggleDialog(billboard);
  }

  // Helper method to compare marker sets
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

  // Throttled proximity checking
  Timer? _proximityTimer;
  void _checkProximityThrottled(Position userPosition, List<Billboard> billboards) {
    _proximityTimer?.cancel();
    _proximityTimer = Timer(Duration(milliseconds: 1000), () {
      _checkProximity(userPosition, billboards);
    });
  }

  void _checkProximity(Position userPosition, List<Billboard> billboards) {
    if (!mounted) return;
    
    for (Billboard billboard in billboards) {
      double distance = Geolocator.distanceBetween(
        userPosition.latitude, userPosition.longitude,
        billboard.latitude, billboard.longitude
      );

      if (distance <= 500) {
        if (!_triggeredBillboards.contains(billboard.billboardId)) {
          _triggerBillboardAlert(billboard);
          _triggeredBillboards.add(billboard.billboardId);
        }
      } else {
        _triggeredBillboards.remove(billboard.billboardId);
      }
    }
  }

  void _triggerBillboardAlert(Billboard billboard) {
    if (!mounted) return;
    
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final index = supabaseService.billboards.indexWhere(
      (b) => b.billboardId == billboard.billboardId,
    );

    if (index != -1) {
      setState(() {
        supabaseService.billboards[index].isActivated = true;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("🚨 EMERGENCY ALERT: Billboard ${billboard.billboardNumber} activated!"),
          backgroundColor: Colors.red,
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _toggleDialog(Billboard billboard) {
    if (_isDialogOpen) {
      _dismissDialog();
    } else {
      _showDialog(billboard);
    }
  }

  void _showDialog(Billboard billboard) {
    setState(() {
      _isDialogOpen = true;
    });
    
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Billboard Control'),
          content: Text(
            billboard.isActivated
                ? 'Do you want to deactivate this billboard?'
                : 'Do you want to manually activate this billboard?'
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _activateOrDeactivateBillboard(billboard);
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
      // Ensure dialog state is reset when dismissed
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

  void _activateOrDeactivateBillboard(Billboard billboard) {
    if (!mounted) return;
    
    final supabaseService = Provider.of<SupabaseService>(context, listen: false);
    final index = supabaseService.billboards.indexWhere(
      (b) => b.billboardId == billboard.billboardId,
    );

    if (index != -1) {
      setState(() {
        supabaseService.billboards[index].isActivated =
            !supabaseService.billboards[index].isActivated;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            billboard.isActivated
                ? "✅ Billboard ${billboard.billboardNumber} manually activated!"
                : "❌ Billboard ${billboard.billboardNumber} manually deactivated!",
          ),
          backgroundColor: billboard.isActivated ? Colors.green : Colors.grey,
          duration: Duration(seconds: 2),
        ),
      );
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
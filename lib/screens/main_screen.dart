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

class MainScreen extends StatefulWidget {
  @override
  _MainScreenState createState() => _MainScreenState();
}

class _MainScreenState extends State<MainScreen> {
  int _selectedIndex = 1; // Start with ALERT tab
  GoogleMapController? _mapController;
  Set<Marker> _markers = {};
  Billboard? _selectedBillboard;
  bool _isDialogOpen = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      supabaseService.loadBillboards();

      // Get current user's email
      final currentUser = Supabase.instance.client.auth.currentUser;
      if (currentUser?.email != null) {
        supabaseService.loadUserData(currentUser!.email!);
      }
    });
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
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (locationService.currentPosition != null && _mapController != null) {
            _mapController?.animateCamera(
              CameraUpdate.newCameraPosition(
                CameraPosition(
                  target: LatLng(
                    locationService.currentPosition!.latitude,
                    locationService.currentPosition!.longitude,
                  ),
                  zoom: 15,
                ),
              ),
            );
            _checkProximity(locationService.currentPosition!, supabaseService.billboards);
          }
        });

        return Column(
          children: [
            // Header with logout
            Container(
              padding: EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(Icons.navigation, size: 24),
                  SizedBox(width: 8),
                  Text(
                    'ALERT TO DIVERT',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  Spacer(),
                  IconButton(
                    icon: Icon(Icons.logout),
                    onPressed: () async {
                      final authService = Provider.of<AuthService>(context, listen: false);
                      await authService.signOut();  // Sign out the user
                      Navigator.pushReplacement(
                        context,
                        MaterialPageRoute(builder: (context) => LoginScreen()),  // Redirect to LoginScreen
                      );
                    },
                  ),
                ],
              ),
            ),
            // Map Container
            Expanded(
              flex: 3,
              child: Container(
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
                      _updateMarkers(supabaseService.billboards);
                    },
                    initialCameraPosition: CameraPosition(
                      target: locationService.currentPosition != null
                          ? LatLng(locationService.currentPosition!.latitude, locationService.currentPosition!.longitude)
                          : LatLng(6.9214, 122.0790), // Default to Zamboanga
                      zoom: 13,
                    ),
                    markers: _markers,
                    onTap: (LatLng position) {
                      setState(() {
                        _selectedBillboard = null;
                      });
                      _dismissDialog();
                    },
                  ),
                ),
              ),
            ),
            // Control Panel
            Expanded(
              flex: 1,
              child: Container(
                padding: EdgeInsets.all(16),
                child: Column(
                  children: [
                    Container(
                      width: double.infinity,
                      height: 60,
                      child: ElevatedButton(
                        onPressed: locationService.isTracking
                            ? locationService.stopTracking
                            : locationService.startTracking,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Color(0xFF8B4B3B),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(30),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              locationService.isTracking ? 'STOP' : 'START',
                              style: TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(width: 8),
                            Icon(locationService.isTracking
                                ? Icons.stop
                                : Icons.play_arrow),
                          ],
                        ),
                      ),
                    ),
                    SizedBox(height: 8),
                    if (locationService.statusMessage.isNotEmpty)
                      Text(
                        locationService.statusMessage,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade600,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  void _updateMarkers(List<Billboard> billboards) {
    setState(() {
      _markers = billboards.map((billboard) {
        return Marker(
          markerId: MarkerId(billboard.billboardId.toString()),
          position: LatLng(billboard.latitude, billboard.longitude),
          onTap: () {
            setState(() {
              _selectedBillboard = billboard;
            });
            _toggleDialog(billboard);
          },
          icon: BitmapDescriptor.defaultMarkerWithHue(
            billboard.isActivated ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed,
          ),
        );
      }).toSet();
    });
  }

  void _checkProximity(Position userPosition, List<Billboard> billboards) {
    for (Billboard billboard in billboards) {
      if (!billboard.isActivated) {
        continue;
      }

      double distance = Geolocator.distanceBetween(
        userPosition.latitude, userPosition.longitude,
        billboard.latitude, billboard.longitude
      );
    
      if (distance <= 500) {
        _activateAlert(billboard);
      }
    }
  }

  void _activateAlert(Billboard billboard) {
    if (billboard.isActivated == false) {
      setState(() {
        billboard.isActivated = true;
        _updateMarkers([billboard]);
      });
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
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Billboard Activation'),
          content: Text(
            billboard.isActivated
                ? 'Do you want to deactivate this billboard?'
                : 'Do you want to activate this billboard?'
          ),
          actions: [
            TextButton(
              onPressed: () {
                _activateOrDeactivateBillboard(billboard);
                Navigator.of(context).pop();
              },
              child: Text(billboard.isActivated ? 'STOP' : 'ACTIVATE'),
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
    );
  }

  void _dismissDialog() {
    setState(() {
      _isDialogOpen = false;
    });
  }

  void _activateOrDeactivateBillboard(Billboard billboard) {
    setState(() {
      final supabaseService = Provider.of<SupabaseService>(context, listen: false);
      final index = supabaseService.billboards.indexWhere(
        (b) => b.billboardId == billboard.billboardId,
      );

      if (index != -1) {
        supabaseService.billboards[index].isActivated =
            !supabaseService.billboards[index].isActivated;
      }

      _updateMarkers(supabaseService.billboards);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          billboard.isActivated
              ? "🚨 Billboard ${billboard.billboardNumber} activated!"
              : "❌ Billboard ${billboard.billboardNumber} deactivated!",
        ),
        backgroundColor: billboard.isActivated ? Colors.orange : Colors.red,
      ),
    );
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

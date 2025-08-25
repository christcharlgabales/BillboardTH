import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:async';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  GoogleMapController? mapController;
  bool gpsActive = false;
  int _selectedIndex = 1; // Default tab = ALERT
  final LatLng initialLocation = const LatLng(8.9475, 125.5406); // Butuan City
  Set<Marker> _markers = {};
  Set<Circle> _circles = {}; // Add circles for billboard radius
  StreamSubscription<Position>? _positionSubscription;
  List<dynamic> _allBillboards = []; // Store all billboard data

  @override
  void initState() {
    super.initState();
    _loadBillboards(); // fetch billboards from Supabase
  }

  /// Load ALL billboards from Supabase (no filtering by distance)
  Future<void> _loadBillboards() async {
    try {
      // Fetch all billboards - Fixed table name to match schema
      final data = await Supabase.instance.client
          .from('billboard')  // Changed from 'Billboard' to 'billboard'
          .select();

      debugPrint("Raw billboard data: $data");
      _allBillboards = data; // Store for proximity checking

      final markers = <Marker>{};
      final circles = <Circle>{};

      for (var billboard in data) {
        try {
          // Fixed column names to match schema
          final id = billboard['billboardid'] as int;  // Changed from 'BillboardID'
          final number = billboard['billboard_number'] as String;  // Changed from 'Billboard_Number'
          final lat = (billboard['latitude'] as num).toDouble();  // Changed from 'Latitude'
          final lng = (billboard['longitude'] as num).toDouble();  // Changed from 'Longitude'

          debugPrint("Billboard $number at ($lat, $lng)");

          // Create marker for billboard
          markers.add(Marker(
            markerId: MarkerId(id.toString()),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(title: "Billboard $number"),
            icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
            onTap: () => _onBillboardTap(id, number, lat, lng),
          ));

          // Create 500m radius circle around billboard
          circles.add(Circle(
            circleId: CircleId("radius_$id"),
            center: LatLng(lat, lng),
            radius: 500, // 500 meters
            fillColor: Colors.red.withOpacity(0.1),
            strokeColor: Colors.red.withOpacity(0.3),
            strokeWidth: 2,
          ));

        } catch (e) {
          debugPrint("Error processing billboard: $e");
          debugPrint("Billboard data: $billboard");
        }
      }

      setState(() {
        _markers = markers;
        _circles = circles;
      });
      debugPrint("Loaded ${markers.length} billboards with 500m radius circles");
      
    } catch (e) {
      debugPrint("Error loading billboards: $e");
    }
  }

  /// Start monitoring EV location and trigger billboard alerts
  Future<void> _startLocationMonitoring() async {
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    if (permission == LocationPermission.whileInUse || 
        permission == LocationPermission.always) {
      
      // Listen to position changes
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // Update every 10 meters
        ),
      ).listen((Position position) {
        _checkBillboardProximity(position);
      });
    }
  }

  /// Check if EV is near any billboard and auto-trigger alerts
  void _checkBillboardProximity(Position evPosition) {
    for (var billboard in _allBillboards) {
      try {
        final id = billboard['billboardid'] as int;
        final number = billboard['billboard_number'] as String;
        final lat = (billboard['latitude'] as num).toDouble();
        final lng = (billboard['longitude'] as num).toDouble();

        // Calculate distance between EV and billboard
        final distance = Geolocator.distanceBetween(
          evPosition.latitude, 
          evPosition.longitude, 
          lat, 
          lng
        );

        debugPrint("EV distance to Billboard $number: ${distance.toStringAsFixed(0)}m");

        // If EV is within 500m of billboard, auto-trigger alert
        if (distance <= 500) {
          debugPrint("🚨 EV ENTERED 500m radius of Billboard $number!");
          _autoActivateBillboard(id, number, distance);
        }
      } catch (e) {
        debugPrint("Error checking proximity for billboard: $e");
      }
    }
  }

  /// Auto-activate billboard alert when EV is nearby
  Future<void> _autoActivateBillboard(int billboardId, String number, double distance) async {
    try {
      // Check if alert already exists to avoid duplicates
      final existingAlert = await Supabase.instance.client
          .from('alerts')
          .select()
          .eq('billboard_id', billboardId)
          .eq('ev_registration_no', "EV-001"); // Replace with actual EV ID

      if (existingAlert.isEmpty) {
        // Insert new alert
        await Supabase.instance.client.from('alerts').insert({
          'billboard_id': billboardId,
          'ev_registration_no': "EV-001", // Replace with logged-in EV
        });

        debugPrint("Auto-activated billboard $number (${distance.toStringAsFixed(0)}m away)");
        
        // Show notification to user
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("🚨 Billboard $number activated! (${distance.toStringAsFixed(0)}m away)"),
              backgroundColor: Colors.orange,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint("Error auto-activating billboard: $e");
    }
  }

  /// Stop location monitoring
  void _stopLocationMonitoring() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Enable GPS when user taps the start button
  Future<void> _toggleGPS() async {
    if (!gpsActive) {
      LocationPermission permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.whileInUse ||
          permission == LocationPermission.always) {
        setState(() => gpsActive = true);
        _startLocationMonitoring(); // Start monitoring EV location
      }
    } else {
      setState(() => gpsActive = false);
      _stopLocationMonitoring(); // Stop monitoring
    }
  }

  /// Show bottom sheet when billboard is tapped
  void _onBillboardTap(int billboardId, String number, double lat, double lng) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        margin: const EdgeInsets.all(16),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF2D1B1B),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.location_on,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        "Billboard Number: $number",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        "Location: Butuan City",
                        style: TextStyle(
                          color: Colors.grey[400],
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(25),
                  ),
                  elevation: 0,
                ),
                onPressed: () async {
                  try {
                    // Insert into alerts table
                    await Supabase.instance.client.from('alerts').insert({
                      'billboard_id': billboardId,
                      'ev_registration_no': "EV-001", // Replace with logged-in EV
                    });
                    
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Alert activated successfully!"),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (mounted) {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text("Failed to activate alert"),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                child: const Text(
                  "ACTIVATE",
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Change bottom navigation index
  void _onNavTap(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  void dispose() {
    _stopLocationMonitoring();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black,
                borderRadius: BorderRadius.circular(20),
              ),
              child: const Icon(
                Icons.headset_mic,
                color: Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              "ALERT TO DIVERT",
              style: TextStyle(
                color: Colors.black,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            // Map Container
            Container(
              height: MediaQuery.of(context).size.height * 0.5,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: GoogleMap(
                  onMapCreated: (controller) => mapController = controller,
                  initialCameraPosition: CameraPosition(
                    target: initialLocation,
                    zoom: 13,
                  ),
                  markers: _markers,
                  circles: _circles, // Add radius circles to map
                  myLocationEnabled: gpsActive,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),
            
            const SizedBox(height: 30),
            
            // Start Button with Controls
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
              decoration: BoxDecoration(
                color: const Color(0xFF2D1B1B),
                borderRadius: BorderRadius.circular(30),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.2),
                    blurRadius: 10,
                    offset: const Offset(0, 5),
                  ),
                ],
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: _toggleGPS,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: gpsActive ? Colors.red : Colors.green,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        gpsActive ? "STOP" : "START",
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                  
                  // Control buttons
                  Row(
                    children: [
                      _buildControlButton(Icons.skip_previous, () {}),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        gpsActive ? Icons.pause : Icons.play_arrow, 
                        _toggleGPS,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(Icons.skip_next, () {}),
                    ],
                  ),
                ],
              ),
            ),
            
            const Spacer(),
          ],
        ),
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 10,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: BottomNavigationBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          currentIndex: _selectedIndex,
          onTap: _onNavTap,
          selectedItemColor: Colors.red,
          unselectedItemColor: Colors.grey,
          type: BottomNavigationBarType.fixed,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.person_outline),
              activeIcon: Icon(Icons.person),
              label: "Profile",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.warning_outlined),
              activeIcon: Icon(Icons.warning),
              label: "ALERT",
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.directions_car_outlined),
              activeIcon: Icon(Icons.directions_car),
              label: "EV Info",
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControlButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.grey[800],
          borderRadius: BorderRadius.circular(20),
        ),
        child: Icon(
          icon,
          color: Colors.white,
          size: 20,
        ),
      ),
    );
  }
}
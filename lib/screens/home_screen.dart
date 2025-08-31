import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

// Push navigation targets
import 'evinfo_screen.dart';
import 'profile_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  // Map
  GoogleMapController? mapController;
  final LatLng fallbackLocation = const LatLng(8.9475, 125.5406); // Butuan fallback
  Set<Marker> _markers = {};
  Set<Circle> _circles = {};

  // GPS
  bool gpsActive = false;
  StreamSubscription<Position>? _positionSubscription;
  Position? _lastPosition;

  // UI
  int _selectedIndex = 1; // 0=Profile, 1=ALERT(Map), 2=EV Info

  // Data
  final SupabaseClient _sb = Supabase.instance.client;
  List<dynamic> _allBillboards = [];
  String? _evRegNo; // pulled from users table for the signed-in user
  String? _userName;
  String? _userRole;

  // Prevent duplicate auto-activations in one session
  final Set<String> _sessionActivated = <String>{};
  
  // Track manually activated billboards for stop functionality
  final Set<int> _manuallyActivated = <int>{};

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();     // get ev_registration_no from users
    _loadBillboards();      // fetch all billboards + draw markers/circles
    _loadActiveAlerts();    // load currently active alerts to update UI
  }

  // -----------------------------
  // Load currently active alerts from database
  // -----------------------------
  Future<void> _loadActiveAlerts() async {
    if (_evRegNo == null || _evRegNo!.isEmpty) return;
    
    try {
      // Get active alerts for current EV from last 30 minutes
      final activeAlerts = await _sb
          .from('alerts')
          .select('billboard_id')
          .eq('ev_registration_no', _evRegNo!)
          .gte('triggered_at',
              DateTime.now().toUtc().subtract(const Duration(minutes: 30)).toIso8601String());

      if (activeAlerts is List && activeAlerts.isNotEmpty) {
        setState(() {
          _manuallyActivated.addAll(
            activeAlerts.map((alert) => alert['billboard_id'] as int)
          );
        });
        _updateMarkerColors();
      }
    } catch (e) {
      debugPrint('Error loading active alerts: $e');
    }
  }

  // -----------------------------
  // Supabase: current user profile
  // -----------------------------
  Future<void> _loadCurrentUser() async {
    try {
      final authUser = _sb.auth.currentUser;
      if (authUser?.email == null) return;

      final rows = await _sb
          .from('users')
          .select('ev_registration_no, name, role')
          .eq('email', authUser!.email!)
          .limit(1);

      if (rows.isNotEmpty) {
        setState(() {
          _evRegNo = rows.first['ev_registration_no'] as String?;
          _userName = rows.first['name'] as String?;
          _userRole = rows.first['role'] as String?;
        });
      }
    } catch (e) {
      debugPrint('Error loading current user: $e');
    }
  }

  // -----------------------------
  // Supabase: billboards -> markers
  // -----------------------------
  Future<void> _loadBillboards() async {
    try {
      final data = await _sb.from('billboard').select();

      _allBillboards = data;
      final markers = <Marker>{};
      final circles = <Circle>{};

      for (final billboard in data) {
        try {
          final id = billboard['billboardid'] as int;
          final number = billboard['billboard_number'] as String;
          final lat = (billboard['latitude'] as num).toDouble();
          final lng = (billboard['longitude'] as num).toDouble();

          // Check if billboard is currently activated
          final isActivated = _manuallyActivated.contains(id);

          markers.add(
            Marker(
              markerId: MarkerId(id.toString()),
              position: LatLng(lat, lng),
              infoWindow: InfoWindow(title: "Billboard $number"),
              icon: BitmapDescriptor.defaultMarkerWithHue(
                isActivated ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed
              ),
              onTap: () => _onBillboardTap(id, number, lat, lng),
            ),
          );

          circles.add(
            Circle(
              circleId: CircleId("radius_$id"),
              center: LatLng(lat, lng),
              radius: 500, // 500 meters
              fillColor: isActivated 
                  ? Colors.green.withOpacity(0.1)
                  : Colors.red.withOpacity(0.1),
              strokeColor: isActivated 
                  ? Colors.green.withOpacity(0.3)
                  : Colors.red.withOpacity(0.3),
              strokeWidth: 2,
            ),
          );
        } catch (e) {
          debugPrint("Error processing billboard row: $e | $billboard");
        }
      }

      setState(() {
        _markers = markers;
        _circles = circles;
      });

      debugPrint("Loaded ${markers.length} billboards with 500m circles");
    } catch (e) {
      debugPrint("Error loading billboards: $e");
    }
  }

  // -----------------------------
  // Update marker colors based on activation status
  // -----------------------------
  void _updateMarkerColors() {
    final updatedMarkers = <Marker>{};
    final updatedCircles = <Circle>{};

    for (final billboard in _allBillboards) {
      try {
        final id = billboard['billboardid'] as int;
        final number = billboard['billboard_number'] as String;
        final lat = (billboard['latitude'] as num).toDouble();
        final lng = (billboard['longitude'] as num).toDouble();

        final isActivated = _manuallyActivated.contains(id);

        updatedMarkers.add(
          Marker(
            markerId: MarkerId(id.toString()),
            position: LatLng(lat, lng),
            infoWindow: InfoWindow(title: "Billboard $number"),
            icon: BitmapDescriptor.defaultMarkerWithHue(
              isActivated ? BitmapDescriptor.hueGreen : BitmapDescriptor.hueRed
            ),
            onTap: () => _onBillboardTap(id, number, lat, lng),
          ),
        );

        updatedCircles.add(
          Circle(
            circleId: CircleId("radius_$id"),
            center: LatLng(lat, lng),
            radius: 500,
            fillColor: isActivated 
                ? Colors.green.withOpacity(0.1)
                : Colors.red.withOpacity(0.1),
            strokeColor: isActivated 
                ? Colors.green.withOpacity(0.3)
                : Colors.red.withOpacity(0.3),
            strokeWidth: 2,
          ),
        );
      } catch (e) {
        debugPrint("Error updating marker: $e");
      }
    }

    setState(() {
      _markers = updatedMarkers;
      _circles = updatedCircles;
    });
  }

  // -----------------------------
  // GPS start/stop + stream
  // -----------------------------
  Future<void> _toggleGPS() async {
    if (!gpsActive) {
      final started = await _startLocationMonitoring();
      if (started) {
        setState(() => gpsActive = true);
      }
    } else {
      _stopLocationMonitoring();
      setState(() => gpsActive = false);
    }
  }

  Future<bool> _startLocationMonitoring() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enable location services to start GPS')),
        );
        return false;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location permission denied')),
        );
        return false;
      }

      // Get initial fix & move camera
      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      );
      _lastPosition = pos;
      _animateTo(LatLng(pos.latitude, pos.longitude), zoom: 15);

      // Stream updates
      _positionSubscription?.cancel();
      _positionSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10, // every 10m
        ),
      ).listen((Position position) {
        _lastPosition = position;
        _checkBillboardProximity(position);
      });

      return true;
    } catch (e) {
      debugPrint('Failed to start GPS: $e');
      return false;
    }
  }

  void _stopLocationMonitoring() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  void _animateTo(LatLng target, {double zoom = 14}) {
    mapController?.animateCamera(
      CameraUpdate.newCameraPosition(
        CameraPosition(target: target, zoom: zoom),
      ),
    );
  }

  // -----------------------------
  // Proximity & activations
  // -----------------------------
  void _checkBillboardProximity(Position evPosition) {
    for (final billboard in _allBillboards) {
      try {
        final id = billboard['billboardid'] as int;
        final number = billboard['billboard_number'] as String;
        final lat = (billboard['latitude'] as num).toDouble();
        final lng = (billboard['longitude'] as num).toDouble();

        final distance = Geolocator.distanceBetween(
          evPosition.latitude, evPosition.longitude, lat, lng,
        );

        if (distance <= 500) {
          final key = '$id:${_evRegNo ?? "-"}';
          if (_sessionActivated.contains(key)) {
            // already activated this billboard in this session
            continue;
          }
          _sessionActivated.add(key);
          _activateAlert(
            billboardId: id,
            billboardNumber: number,
            activationType: 'auto',
            distanceMeters: distance,
          );
        }
      } catch (e) {
        debugPrint("Proximity error: $e");
      }
    }
  }

  Future<void> _activateAlert({
    required int billboardId,
    required String billboardNumber,
    required String activationType, // 'manual' or 'auto'
    double? distanceMeters,
  }) async {
    if (_evRegNo == null || _evRegNo!.isEmpty) {
      // The user doesn't have an EV linked
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Link an EV to your account first (EV Info)."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Avoid duplicates in DB for same billboard+EV in a short time
      final existing = await _sb
          .from('alerts')
          .select()
          .eq('billboard_id', billboardId)
          .eq('ev_registration_no', _evRegNo!)
          .gte('triggered_at',
              DateTime.now().toUtc().subtract(const Duration(minutes: 5)).toIso8601String());

      if (existing is List && existing.isNotEmpty) {
        return; // already inserted recently
      }

      // Insert into alerts
      await _sb.from('alerts').insert({
        'billboard_id': billboardId,
        'ev_registration_no': _evRegNo!,
        'triggered_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Insert into alertlog (so it appears in Profile logs)
      await _sb.from('alertlog').insert({
        'date': DateTime.now().toLocal().toIso8601String().split('T').first, // YYYY-MM-DD
        'time': TimeOfDay.now().format(context), // stored as text in your schema (time)
        'billboardid': billboardId,
        'ev_registration_no': _evRegNo!,
        'type_of_activation': activationType,
        'result': 'Success',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Add to manually activated set and update markers
      if (activationType == 'manual') {
        setState(() {
          _manuallyActivated.add(billboardId);
        });
        _updateMarkerColors();
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              activationType == 'auto'
                  ? "🚨 Billboard $billboardNumber activated automatically!"
                  : "Alert activated for Billboard $billboardNumber",
            ),
            backgroundColor: activationType == 'auto' ? Colors.orange : Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Activate alert error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to activate alert"),
            backgroundColor: Colors.red,
          ),
        );
      }
      // Optional: log failed attempt
      try {
        await _sb.from('alertlog').insert({
          'date': DateTime.now().toLocal().toIso8601String().split('T').first,
          'time': TimeOfDay.now().format(context),
          'billboardid': billboardId,
          'ev_registration_no': _evRegNo ?? '',
          'type_of_activation': activationType,
          'result': 'Failed',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        });
      } catch (_) {}
    }
  }

  // -----------------------------
  // Deactivate/Stop alert function
  // -----------------------------
  Future<void> _deactivateAlert({
    required int billboardId,
    required String billboardNumber,
  }) async {
    if (_evRegNo == null || _evRegNo!.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("No EV linked to your account."),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    try {
      // Remove active alerts for this billboard and EV
      await _sb
          .from('alerts')
          .delete()
          .eq('billboard_id', billboardId)
          .eq('ev_registration_no', _evRegNo!);

      // Log the deactivation
      await _sb.from('alertlog').insert({
        'date': DateTime.now().toLocal().toIso8601String().split('T').first,
        'time': TimeOfDay.now().format(context),
        'billboardid': billboardId,
        'ev_registration_no': _evRegNo!,
        'type_of_activation': 'manual_stop',
        'result': 'Success',
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });

      // Remove from manually activated set and update markers
      setState(() {
        _manuallyActivated.remove(billboardId);
      });
      _updateMarkerColors();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Alert stopped for Billboard $billboardNumber"),
            backgroundColor: Colors.blue,
          ),
        );
      }
    } catch (e) {
      debugPrint('Deactivate alert error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Failed to stop alert"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // -----------------------------
  // Bottom sheet on marker tap - Updated with Stop functionality
  // -----------------------------
  void _onBillboardTap(int billboardId, String number, double lat, double lng) {
    final bool isActivated = _manuallyActivated.contains(billboardId);
    
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
                    color: isActivated ? Colors.green : Colors.red,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(
                    isActivated ? Icons.check_circle : Icons.location_on,
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
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        "Lat: ${lat.toStringAsFixed(5)}, Lng: ${lng.toStringAsFixed(5)}",
                        style: TextStyle(color: Colors.grey[400], fontSize: 14),
                      ),
                      if (isActivated)
                        Text(
                          "Status: ACTIVE",
                          style: TextStyle(color: Colors.green[300], fontSize: 12, fontWeight: FontWeight.bold),
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
                  backgroundColor: isActivated ? Colors.blue : Colors.red,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                  elevation: 0,
                ),
                onPressed: () async {
                  Navigator.pop(context);
                  if (isActivated) {
                    // Stop/Deactivate the alert
                    await _deactivateAlert(
                      billboardId: billboardId,
                      billboardNumber: number,
                    );
                  } else {
                    // Activate the alert
                    await _activateAlert(
                      billboardId: billboardId,
                      billboardNumber: number,
                      activationType: 'manual',
                    );
                  }
                },
                child: Text(
                  isActivated ? "STOP" : "ACTIVATE",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // -----------------------------
  // Bottom navigation
  // -----------------------------
  void _onNavTap(int index) async {
    setState(() => _selectedIndex = index);
    if (index == 0) {
      // Profile
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const ProfileScreen()),
      );
      setState(() => _selectedIndex = 1);
    } else if (index == 2) {
      // EV Info
      await Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const EVInfoScreen()),
      );
      setState(() => _selectedIndex = 1);
    }
  }

  // -----------------------------
  // Lifecycle
  // -----------------------------
  @override
  void dispose() {
    _stopLocationMonitoring();
    super.dispose();
  }

  // -----------------------------
  // UI
  // -----------------------------
  @override
  Widget build(BuildContext context) {
    final titleLine = (_userName != null && _userRole != null)
        ? "$_userName — ${_userRole!}"
        : "ALERT TO DIVERT";

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
                color: Colors.black, borderRadius: BorderRadius.circular(20)),
              child: const Icon(Icons.headset_mic, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 12),
            Text(
              titleLine,
              style: const TextStyle(
                color: Colors.black, fontSize: 18, fontWeight: FontWeight.bold),
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
                    target: _lastPosition != null
                        ? LatLng(_lastPosition!.latitude, _lastPosition!.longitude)
                        : fallbackLocation,
                    zoom: 13,
                  ),
                  markers: _markers,
                  circles: _circles,
                  myLocationEnabled: gpsActive,
                  myLocationButtonEnabled: false,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
            ),

            const SizedBox(height: 30),

            // Start/Stop + controls
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
                          color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      _buildControlButton(Icons.my_location, () async {
                        try {
                          final p = await Geolocator.getCurrentPosition();
                          _animateTo(LatLng(p.latitude, p.longitude), zoom: 16);
                        } catch (_) {}
                      }),
                      const SizedBox(width: 12),
                      _buildControlButton(
                        gpsActive ? Icons.pause : Icons.play_arrow,
                        _toggleGPS,
                      ),
                      const SizedBox(width: 12),
                      _buildControlButton(Icons.refresh, () {
                        _loadBillboards();
                        _loadActiveAlerts();
                      }),
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
          color: Colors.grey[800], borderRadius: BorderRadius.circular(20)),
        child: Icon(icon, color: Colors.white, size: 20),
      ),
    );
  }
}
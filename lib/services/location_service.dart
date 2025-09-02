import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';
import 'dart:async';

class LocationService extends ChangeNotifier {
  Position? _currentPosition;
  bool isTracking = false;
  String statusMessage = '';
  StreamSubscription<Position>? _positionStream;
  Timer? _statusUpdateTimer;
  
  // Performance optimization variables
  Position? _lastNotifiedPosition;
  DateTime? _lastUpdateTime;
  static const double _minimumDistanceForUpdate = 10.0; // 10 meters
  static const Duration _minimumTimeForUpdate = Duration(seconds: 2);
  
  Position? get currentPosition => _currentPosition;

  // Start tracking the location with optimized settings
  Future<void> startTracking() async {
    if (isTracking) return; // Prevent duplicate tracking
    
    try {
      // Check permissions first
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        statusMessage = 'Location services are disabled';
        notifyListeners();
        return;
      }

      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }

      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        statusMessage = 'Location permission denied';
        notifyListeners();
        return;
      }

      // Get initial position with progressive fallback
      try {
        _currentPosition = await Geolocator.getCurrentPosition(
          desiredAccuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15), // Increased timeout
        );
      } catch (e) {
        print('High accuracy failed, trying medium: $e');
        try {
          // Fallback to medium accuracy
          _currentPosition = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.medium,
            timeLimit: Duration(seconds: 10),
          );
        } catch (e2) {
          print('Medium accuracy failed, trying low: $e2');
          try {
            // Final fallback to low accuracy
            _currentPosition = await Geolocator.getCurrentPosition(
              desiredAccuracy: LocationAccuracy.low,
              timeLimit: Duration(seconds: 8),
            );
          } catch (e3) {
            print('All accuracy levels failed: $e3');
            // Try to get last known position
            _currentPosition = await Geolocator.getLastKnownPosition();
            if (_currentPosition == null) {
              throw Exception('Unable to get any location data');
            }
          }
        }
      }
      
      isTracking = true;
      statusMessage = 'GPS Tracking Started';
      _lastUpdateTime = DateTime.now();
      notifyListeners();
      
      print('🟢 GPS Tracking Started - Initial Position: ${_currentPosition!.latitude}, ${_currentPosition!.longitude}');
      
      // Start continuous tracking with optimized settings
      _trackLocationContinuously();
      
    } catch (e) {
      statusMessage = 'Failed to start tracking: $e';
      isTracking = false;
      notifyListeners();
      print('❌ Error starting GPS tracking: $e');
    }
  }

  // Stop tracking
  Future<void> stopTracking() async {
    if (!isTracking) return;
    
    isTracking = false;
    statusMessage = 'GPS Tracking Stopped';
    
    // Cancel the position stream
    await _positionStream?.cancel();
    _positionStream = null;
    
    // Cancel status update timer
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = null;
    
    notifyListeners();
    print('🔴 GPS Tracking Stopped');
  }

  // Continuously track the user's location with performance optimizations
  void _trackLocationContinuously() {
    // Cancel existing stream if any
    _positionStream?.cancel();
    
    _positionStream = Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.medium, // Changed from high to medium for better battery life
        distanceFilter: 10, // Increased from 8 to 10 meters
        timeLimit: Duration(seconds: 20), // Increased timeout
      ),
    ).listen(
      (Position position) {
        _handlePositionUpdate(position);
      },
      onError: (error) {
        _handleLocationError(error);
      },
    );
    
    // Set up periodic status updates (less frequent)
    _statusUpdateTimer?.cancel();
    _statusUpdateTimer = Timer.periodic(Duration(seconds: 30), (timer) {
      if (isTracking && mounted) {
        statusMessage = 'Location tracking active';
        notifyListeners();
      }
    });
  }

  // Add mounted check to prevent updates after disposal
  bool get mounted => !(_positionStream?.isPaused ?? true) || isTracking;

  // Optimized position update handling
  void _handlePositionUpdate(Position position) {
    final now = DateTime.now();
    
    // Check if we should update based on distance and time
    bool shouldUpdate = true;
    
    if (_lastNotifiedPosition != null && _lastUpdateTime != null) {
      final distance = Geolocator.distanceBetween(
        _lastNotifiedPosition!.latitude,
        _lastNotifiedPosition!.longitude,
        position.latitude,
        position.longitude,
      );
      
      final timeDiff = now.difference(_lastUpdateTime!);
      
      // Only update if moved significant distance OR enough time has passed
      shouldUpdate = distance >= _minimumDistanceForUpdate || 
                    timeDiff >= _minimumTimeForUpdate;
    }
    
    // Always update current position for accuracy
    _currentPosition = position;
    
    // Only notify listeners if significant change
    if (shouldUpdate) {
      _lastNotifiedPosition = position;
      _lastUpdateTime = now;
      
      // Update status message less frequently
      if (_statusUpdateTimer == null || !_statusUpdateTimer!.isActive) {
        statusMessage = 'Location tracking active';
      }
      
      notifyListeners();
      
      // Reduced logging frequency
      if (kDebugMode && now.millisecondsSinceEpoch % 10000 < 1000) {
        print('📍 Location Update: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}');
      }
    }
  }

  // Handle location errors with retry logic
  void _handleLocationError(dynamic error) {
    print('❌ Location stream error: $error');
    
    // Update status but don't spam notifications
    if (statusMessage != 'Location error occurred') {
      statusMessage = 'Location error occurred';
      notifyListeners();
    }
    
    // Implement retry logic for transient errors
    if (isTracking) {
      Timer(Duration(seconds: 5), () {
        if (isTracking && (_positionStream?.isPaused ?? true)) {
          print('🔄 Retrying location tracking...');
          _trackLocationContinuously();
        }
      });
    }
  }

  // Get current position on demand (cached version)
  Future<Position?> getCurrentPosition() async {
    if (_currentPosition != null) {
      final age = DateTime.now().millisecondsSinceEpoch - _currentPosition!.timestamp.millisecondsSinceEpoch;
      
      // Return cached position if it's less than 30 seconds old
      if (age < 30000) {
        return _currentPosition;
      }
    }
    
    try {
      final position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.medium,
        timeLimit: Duration(seconds: 5),
      );
      _currentPosition = position;
      return position;
    } catch (e) {
      print('Error getting current position: $e');
      return _currentPosition; // Return last known position
    }
  }

  // Check if location services are available
  Future<bool> isLocationAvailable() async {
    try {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) return false;
      
      LocationPermission permission = await Geolocator.checkPermission();
      return permission != LocationPermission.denied && 
             permission != LocationPermission.deniedForever;
    } catch (e) {
      return false;
    }
  }

  // Get distance to a point (utility method)
  double? getDistanceTo(double latitude, double longitude) {
    if (_currentPosition == null) return null;
    
    return Geolocator.distanceBetween(
      _currentPosition!.latitude,
      _currentPosition!.longitude,
      latitude,
      longitude,
    );
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _statusUpdateTimer?.cancel();
    super.dispose();
  }
}
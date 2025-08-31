import 'package:geolocator/geolocator.dart';
import 'package:flutter/foundation.dart';

class LocationService extends ChangeNotifier {
  Position? _currentPosition;
  bool isTracking = false;
  String statusMessage = '';
  Position? get currentPosition => _currentPosition;

  // Start tracking the location
  Future<void> startTracking() async {
    isTracking = true;
    statusMessage = 'Tracking Started';
    notifyListeners();
    await _getCurrentLocation();
  }

  // Stop tracking
  Future<void> stopTracking() async {
    isTracking = false;
    statusMessage = 'Tracking Stopped';
    notifyListeners();
  }

  // Fetch current location
  Future<void> _getCurrentLocation() async {
    try {
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

      // Fetch the current location
      _currentPosition = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.high);
      statusMessage = 'Location fetched';
      notifyListeners();
    } catch (e) {
      statusMessage = 'Failed to get location: $e';
      notifyListeners();
    }
  }
}

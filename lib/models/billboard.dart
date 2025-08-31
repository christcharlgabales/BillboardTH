class Billboard {
  final int billboardId;
  final String billboardNumber;
  final String location;
  final double latitude;
  final double longitude;
  bool isActivated;

  Billboard({
    required this.billboardId,
    required this.billboardNumber,
    required this.location,
    required this.latitude,
    required this.longitude,
    this.isActivated = false, // Default to false (not activated)
  });

  // From JSON parsing if needed
  factory Billboard.fromJson(Map<String, dynamic> json) {
    return Billboard(
      billboardId: json['billboardid'],
      billboardNumber: json['billboard_number'],
      location: json['location'],
      latitude: json['latitude'],
      longitude: json['longitude'],
      isActivated: json['isActivated'] ?? false, // Default false if null
    );
  }

  // To JSON if you need to send it back to Supabase
  Map<String, dynamic> toJson() {
    return {
      'billboardid': billboardId,
      'billboard_number': billboardNumber,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'isActivated': isActivated,
    };
  }
}

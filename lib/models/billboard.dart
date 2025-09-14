class Billboard {
  final int billboardId;
  final String billboardNumber;
  final String location;
  final double latitude;
  final double longitude;
  final DateTime createdAt;
  bool isActivated;

  Billboard({
    required this.billboardId,
    required this.billboardNumber,
    required this.location,
    required this.latitude,
    required this.longitude,
    required this.createdAt,
    this.isActivated = false,
  });

  factory Billboard.fromJson(Map<String, dynamic> json) {
    return Billboard(
      billboardId: json['billboardid'] as int,
      billboardNumber: json['billboard_number'] as String,
      location: json['location'] as String,
      latitude: double.parse(json['latitude'].toString()),
      longitude: double.parse(json['longitude'].toString()),
      createdAt: DateTime.parse(json['created_at'] as String),
      isActivated: _parseBool(json['is_activated']),
    );
  }
static bool _parseBool(dynamic value) {
  if (value == null) return false;
  if (value is bool) return value;
  if (value is String) {
    return value.toLowerCase() == 'true' || value == '1';
  }
  if (value is int) return value == 1;
  return false;
}

  // To JSON if you need to send it back to Supabase
  Map<String, dynamic> toJson() {
    return {
      'billboardid': billboardId,
      'billboard_number': billboardNumber,
      'location': location,
      'latitude': latitude,
      'longitude': longitude,
      'is_activated': isActivated,
    };
  }
}

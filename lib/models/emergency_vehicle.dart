class EmergencyVehicle {
  final String evRegistrationNo;
  final String evType;
  final String agency;
  final String plateNumber;
  final DateTime createdAt;

  EmergencyVehicle({
    required this.evRegistrationNo,
    required this.evType,
    required this.agency,
    required this.plateNumber,
    required this.createdAt,
  });

  factory EmergencyVehicle.fromJson(Map<String, dynamic> json) {
    return EmergencyVehicle(
      evRegistrationNo: json['ev_registration_no'] as String,
      evType: json['ev_type'] as String,
      agency: json['agency'] as String,
      plateNumber: json['plate_number'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
    );
  }
}
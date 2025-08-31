class EmergencyVehicle {
  final String evRegistrationNo;
  final String evType;
  final String agency;
  final String plateNumber;

  EmergencyVehicle({
    required this.evRegistrationNo,
    required this.evType,
    required this.agency,
    required this.plateNumber,
  });

  factory EmergencyVehicle.fromJson(Map<String, dynamic> json) {
    return EmergencyVehicle(
      evRegistrationNo: json['ev_registration_no'] ?? '',
      evType: json['ev_type'] ?? '',
      agency: json['agency'] ?? '',
      plateNumber: json['plate_number'] ?? '',
    );
  }
}
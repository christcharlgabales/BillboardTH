class AppUser {
  final String email;
  final String name;
  final String role;
  final String evRegistrationNo;
  final String status;
  final DateTime createdAt;
  final String userId;

  AppUser({
    required this.email,
    required this.name,
    required this.role,
    required this.evRegistrationNo,
    required this.status,
    required this.createdAt,
    required this.userId,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      email: json['email'] as String,
      name: json['name'] as String,
      role: json['role'] as String,
      evRegistrationNo: json['ev_registration_no'] as String,
      status: json['status'] as String,
      createdAt: DateTime.parse(json['created_at'] as String),
      userId: json['userid'] as String,
    );
  }
}
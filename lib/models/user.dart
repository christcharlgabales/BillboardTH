class AppUser {
  final int userId;
  final String name;
  final String email;
  final String role;
  final String evRegistrationNo;

  AppUser({
    required this.userId,
    required this.name,
    required this.email,
    required this.role,
    required this.evRegistrationNo,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      userId: json['userid'] ?? 0,
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      role: json['role'] ?? '',
      evRegistrationNo: json['ev_registration_no'] ?? '',
    );
  }
}
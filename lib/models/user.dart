// user.dart

class AppUser {
  final String email;
  final String name;
  final String role;
  final String evRegistrationNo;
  final String status;
  final DateTime createdAt;
  final String userId;
  final String? avatarUrl; // Add avatar URL field

  AppUser({
    required this.email,
    required this.name,
    required this.role,
    required this.evRegistrationNo,
    required this.status,
    required this.createdAt,
    required this.userId,
    this.avatarUrl, // Add avatar URL parameter
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
      avatarUrl: json['avatar_url'] as String?, // Add avatar URL parsing
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'email': email,
      'name': name,
      'role': role,
      'ev_registration_no': evRegistrationNo,
      'status': status,
      'created_at': createdAt.toIso8601String(),
      'userid': userId,
      'avatar_url': avatarUrl, // Include avatar URL in JSON
    };
  }

  // Add copyWith method for easy updates
  AppUser copyWith({
    String? email,
    String? name,
    String? role,
    String? evRegistrationNo,
    String? status,
    DateTime? createdAt,
    String? userId,
    String? avatarUrl,
  }) {
    return AppUser(
      email: email ?? this.email,
      name: name ?? this.name,
      role: role ?? this.role,
      evRegistrationNo: evRegistrationNo ?? this.evRegistrationNo,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      userId: userId ?? this.userId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
    );
  }
}
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
      email: json['email'] as String? ?? '', // Handle null with default value
      name: json['name'] as String? ?? 'Unknown', // Handle null with default value
      role: json['role'] as String? ?? 'user', // Handle null with default value
      evRegistrationNo: json['ev_registration_no'] as String? ?? '', // Handle null with default value
      status: json['status'] as String? ?? 'inactive', // Handle null with default value
      createdAt: json['created_at'] != null 
          ? DateTime.parse(json['created_at'] as String)
          : DateTime.now(), // Handle null created_at
      userId: json['userid'] as String? ?? '', // Handle null with default value
      avatarUrl: json['avatar_url'] as String?, // This can remain nullable
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
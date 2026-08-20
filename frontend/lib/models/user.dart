/// Core customer user model (backend `users.User`).
class User {
  const User({
    required this.id,
    this.email,
    this.phone,
    required this.firstName,
    required this.lastName,
    this.avatarMediaId,
    this.avatarUrl,
    required this.role,
    required this.status,
    required this.emailVerified,
    required this.phoneVerified,
    this.createdAt,
  });

  factory User.fromJson(Map<String, dynamic> json) {
    return User(
      id: json['id'] as String? ?? '',
      email: json['email'] as String?,
      phone: json['phone'] as String?,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      avatarMediaId: json['avatar_media_id'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      role: json['role'] as String? ?? 'CUSTOMER',
      status: json['status'] as String? ?? 'ACTIVE',
      emailVerified: json['email_verified'] as bool? ?? false,
      phoneVerified: json['phone_verified'] as bool? ?? false,
      createdAt: json['created_at'] != null ? DateTime.tryParse(json['created_at'] as String) : null,
    );
  }

  final String id;
  final String? email;
  final String? phone;
  final String firstName;
  final String lastName;
  final String? avatarMediaId;
  final String? avatarUrl;
  final String role;
  final String status;
  final bool emailVerified;
  final bool phoneVerified;
  final DateTime? createdAt;

  String get fullName => [firstName, lastName].where((s) => s.isNotEmpty).join(' ');

  /// A customer is considered verified only once both email and phone are
  /// confirmed.
  bool get isVerified => emailVerified && phoneVerified;

  User copyWith({
    String? id,
    String? email,
    String? phone,
    String? firstName,
    String? lastName,
    String? avatarMediaId,
    String? avatarUrl,
    String? role,
    String? status,
    bool? emailVerified,
    bool? phoneVerified,
    DateTime? createdAt,
  }) {
    return User(
      id: id ?? this.id,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      firstName: firstName ?? this.firstName,
      lastName: lastName ?? this.lastName,
      avatarMediaId: avatarMediaId ?? this.avatarMediaId,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      role: role ?? this.role,
      status: status ?? this.status,
      emailVerified: emailVerified ?? this.emailVerified,
      phoneVerified: phoneVerified ?? this.phoneVerified,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'email': email,
        'phone': phone,
        'first_name': firstName,
        'last_name': lastName,
        'avatar_media_id': avatarMediaId,
        'avatar_url': avatarUrl,
        'role': role,
        'status': status,
        'email_verified': emailVerified,
        'phone_verified': phoneVerified,
        'created_at': createdAt?.toIso8601String(),
      };
}

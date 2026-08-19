/// Nested user of a professional public profile (backend `PublicProfile.User`).
class ProfessionalUser {
  const ProfessionalUser({
    this.firstName = '',
    this.lastName = '',
    this.avatarMediaId,
  });

  factory ProfessionalUser.fromJson(Map<String, dynamic> json) {
    return ProfessionalUser(
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      avatarMediaId: json['avatar_media_id'] as String?,
    );
  }

  final String firstName;
  final String lastName;
  final String? avatarMediaId;

  String get fullName => [firstName, lastName].where((s) => s.isNotEmpty).join(' ');
}

/// Beauty professional / artist (backend `professionals.Professional`).
/// `user` is only populated by the detail endpoint (`/professionals/{id}`).
class Professional {
  const Professional({
    required this.id,
    required this.userId,
    this.businessName = '',
    this.displayName = '',
    this.bio = '',
    this.categoryId,
    this.experienceYears,
    this.rating = 0,
    this.reviewCount = 0,
    this.bookingCount = 0,
    this.completionRate = 0,
    this.status = 'PENDING',
    this.verificationStatus = 'UNVERIFIED',
    this.trustScore = 0,
    this.latitude,
    this.longitude,
    this.addressLine = '',
    this.city = '',
    this.country = '',
    this.timezone = '',
    this.homeServiceEnabled = false,
    this.serviceRadiusKm,
    this.travelFeePerKm = 0,
    this.createdAt,
    this.updatedAt,
    this.user,
  });

  factory Professional.fromJson(Map<String, dynamic> json) {
    final userJson = json['user'];
    return Professional(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      businessName: json['business_name'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      bio: json['bio'] as String? ?? '',
      categoryId: json['category_id'] as String?,
      experienceYears: (json['experience_years'] as num?)?.toInt(),
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
      reviewCount: (json['review_count'] as num?)?.toInt() ?? 0,
      bookingCount: (json['booking_count'] as num?)?.toInt() ?? 0,
      completionRate: (json['completion_rate'] as num?)?.toDouble() ?? 0,
      status: json['status'] as String? ?? 'PENDING',
      verificationStatus: json['verification_status'] as String? ?? 'UNVERIFIED',
      trustScore: (json['trust_score'] as num?)?.toDouble() ?? 0,
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      addressLine: json['address_line'] as String? ?? '',
      city: json['city'] as String? ?? '',
      country: json['country'] as String? ?? '',
      timezone: json['timezone'] as String? ?? '',
      homeServiceEnabled: json['home_service_enabled'] as bool? ?? false,
      serviceRadiusKm: (json['service_radius_km'] as num?)?.toDouble(),
      travelFeePerKm: (json['travel_fee_per_km'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      user: userJson is Map<String, dynamic> ? ProfessionalUser.fromJson(userJson) : null,
    );
  }

  final String id;
  final String userId;
  final String businessName;
  final String displayName;
  final String bio;
  final String? categoryId;
  final int? experienceYears;
  final double rating;
  final int reviewCount;
  final int bookingCount;
  final double completionRate;
  final String status;
  final String verificationStatus;
  final double trustScore;
  final double? latitude;
  final double? longitude;
  final String addressLine;
  final String city;
  final String country;
  final String timezone;
  final bool homeServiceEnabled;
  final double? serviceRadiusKm;
  final double travelFeePerKm;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final ProfessionalUser? user;

  /// Display name falling back to the business name.
  String get name => displayName.isNotEmpty ? displayName : businessName;

  bool get verified => verificationStatus.toUpperCase() == 'VERIFIED';

  bool get isActive => status.toUpperCase() == 'ACTIVE';

  String get location => [city, country].where((s) => s.isNotEmpty).join(', ');
}

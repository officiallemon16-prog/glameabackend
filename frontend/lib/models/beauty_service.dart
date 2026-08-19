/// A bookable beauty service (backend `services.Service`).
class BeautyService {
  const BeautyService({
    required this.id,
    required this.professionalId,
    required this.name,
    this.categoryId,
    this.description = '',
    this.basePrice = 0,
    this.currency = 'NGN',
    this.durationMinutes = 60,
    this.depositPercentage = 0,
    this.homeServiceAvailable = false,
    this.displayOrder = 0,
    this.isActive = true,
  });

  factory BeautyService.fromJson(Map<String, dynamic> json) {
    return BeautyService(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      categoryId: json['category_id'] as String?,
      description: json['description'] as String? ?? '',
      basePrice: (json['base_price'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'NGN',
      durationMinutes: (json['duration_minutes'] as num?)?.toInt() ?? 60,
      depositPercentage: (json['deposit_percentage'] as num?)?.toDouble() ?? 0,
      homeServiceAvailable: json['home_service_available'] as bool? ?? false,
      displayOrder: (json['display_order'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  final String id;
  final String professionalId;
  final String name;
  final String? categoryId;
  final String description;
  final double basePrice;
  final String currency;
  final int durationMinutes;
  final double depositPercentage;
  final bool homeServiceAvailable;
  final int displayOrder;
  final bool isActive;
}

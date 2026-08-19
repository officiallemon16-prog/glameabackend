/// Promotional offer/deal (backend `deals.Deal`).
class Deal {
  const Deal({
    required this.id,
    required this.professionalId,
    required this.code,
    required this.name,
    this.discountType = 'PERCENT',
    this.discountValue = 0,
    this.minOrderAmount = 0,
    this.timesUsed = 0,
    this.isActive = true,
  });

  factory Deal.fromJson(Map<String, dynamic> json) {
    return Deal(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      code: json['code'] as String? ?? '',
      name: json['name'] as String? ?? '',
      discountType: json['discount_type'] as String? ?? 'PERCENT',
      discountValue: (json['discount_value'] as num?)?.toDouble() ?? 0,
      minOrderAmount: (json['min_order_amount'] as num?)?.toDouble() ?? 0,
      timesUsed: (json['times_used'] as num?)?.toInt() ?? 0,
      isActive: json['is_active'] as bool? ?? true,
    );
  }

  final String id;
  final String professionalId;
  final String code;
  final String name;
  final String discountType;
  final double discountValue;
  final double minOrderAmount;
  final int timesUsed;
  final bool isActive;

  bool get isPercent => discountType.toUpperCase() == 'PERCENT';

  /// Short badge, e.g. "-10%" for percentage deals.
  String get badgeLabel => isPercent ? '-${discountValue.round()}%' : '-${discountValue.toStringAsFixed(0)}';
}

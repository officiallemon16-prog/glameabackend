/// A customer review of a professional (backend `reviews.Review`).
class Review {
  const Review({
    required this.id,
    required this.professionalId,
    required this.rating,
    this.bookingId = '',
    this.customerId,
    this.serviceId,
    this.comment = '',
    this.response,
    this.respondedAt,
    this.customerName = '',
    this.professionalName = '',
    this.createdAt,
  });

  factory Review.fromJson(Map<String, dynamic> json) {
    return Review(
      id: json['id'] as String? ?? '',
      bookingId: json['booking_id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      customerId: json['customer_id'] as String?,
      serviceId: json['service_id'] as String?,
      rating: (json['rating'] as num?)?.toInt() ?? 0,
      comment: json['comment'] as String? ?? '',
      response: json['response'] as String?,
      respondedAt: DateTime.tryParse(json['responded_at'] as String? ?? ''),
      customerName: json['customer_name'] as String? ?? '',
      professionalName: json['professional_name'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String bookingId;
  final String professionalId;
  final String? customerId;
  final String? serviceId;
  final int rating;
  final String comment;
  final String? response;
  final DateTime? respondedAt;
  final String customerName;
  final String professionalName;
  final DateTime? createdAt;
}

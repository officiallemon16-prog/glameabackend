/// A booking of a service with a professional (backend `bookings.Booking`).
class Booking {
  const Booking({
    required this.id,
    required this.professionalId,
    required this.customerId,
    required this.serviceId,
    required this.status,
    required this.startAt,
    required this.endAt,
    required this.baseAmount,
    required this.totalAmount,
    required this.depositAmount,
    required this.balanceAmount,
    required this.currency,
    required this.homeService,
    this.variantId,
    this.locationLat,
    this.locationLng,
    this.locationAddress = '',
    this.customerNotes = '',
    this.cancellationPolicyId,
    this.cancelledAt,
    this.cancelledBy,
    this.cancelReason = '',
    this.createdAt,
    this.updatedAt,
    this.serviceName = '',
    this.professionalName = '',
    this.customerName = '',
  });

  factory Booking.fromJson(Map<String, dynamic> json) {
    final total = (json['total_amount'] as num?)?.toDouble() ?? 0;
    final deposit = (json['deposit_amount'] as num?)?.toDouble() ?? 0;
    return Booking(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      customerId: json['customer_id'] as String? ?? '',
      serviceId: json['service_id'] as String? ?? '',
      variantId: json['variant_id'] as String?,
      status: json['status'] as String? ?? 'PENDING',
      startAt: DateTime.tryParse(json['start_at'] as String? ?? ''),
      endAt: DateTime.tryParse(json['end_at'] as String? ?? ''),
      baseAmount: (json['base_amount'] as num?)?.toDouble() ?? 0,
      totalAmount: total,
      depositAmount: deposit,
      // The backend computes the outstanding balance from every SUCCEEDED
      // payment intent; fall back to total - deposit when it is absent.
      balanceAmount: (json['balance_amount'] as num?)?.toDouble() ?? (total - deposit),
      currency: json['currency'] as String? ?? 'NGN',
      homeService: json['home_service'] as bool? ?? false,
      locationLat: (json['location_lat'] as num?)?.toDouble(),
      locationLng: (json['location_lng'] as num?)?.toDouble(),
      locationAddress: json['location_address'] as String? ?? '',
      customerNotes: json['customer_notes'] as String? ?? '',
      cancellationPolicyId: json['cancellation_policy_id'] as String?,
      cancelledAt: DateTime.tryParse(json['cancelled_at'] as String? ?? ''),
      cancelledBy: json['cancelled_by'] as String?,
      cancelReason: json['cancel_reason'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
      serviceName: json['service_name'] as String? ?? '',
      professionalName: json['professional_name'] as String? ?? '',
      customerName: json['customer_name'] as String? ?? '',
    );
  }

  final String id;
  final String professionalId;
  final String customerId;
  final String serviceId;
  final String? variantId;
  final String status;
  final DateTime? startAt;
  final DateTime? endAt;
  final double baseAmount;
  final double totalAmount;
  final double depositAmount;
  final double balanceAmount;
  final String currency;
  final bool homeService;
  final double? locationLat;
  final double? locationLng;
  final String locationAddress;
  final String customerNotes;
  final String? cancellationPolicyId;
  final DateTime? cancelledAt;
  final String? cancelledBy;
  final String cancelReason;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String serviceName;
  final String professionalName;
  final String customerName;

  bool get isPending => status == 'PENDING';
  bool get isConfirmed => status == 'CONFIRMED';
  bool get isCompleted => status == 'COMPLETED';
  bool get isCancelled => status == 'CANCELLED';
  bool get isNoShow => status == 'NO_SHOW';

  bool get isUpcoming => isPending || isConfirmed;

  /// Only active bookings can be cancelled by the customer.
  bool get cancellable => isUpcoming;

  /// Only active bookings can be rescheduled by the customer.
  bool get reschedulable => isUpcoming;

  /// Messaging is available while the booking is not finished/cancelled.
  bool get canMessage => !isCancelled && !isNoShow;

  /// Completed bookings can be reviewed by the customer.
  bool get canReview => isCompleted;

  /// Disputes are offered once a booking is finished (completed or no-show).
  bool get canDispute => isCompleted || isNoShow;

  String get statusLabel {
    switch (status) {
      case 'PENDING':
        return 'Pending';
      case 'CONFIRMED':
        return 'Confirmed';
      case 'IN_PROGRESS':
        return 'In progress';
      case 'COMPLETED':
        return 'Completed';
      case 'CANCELLED':
        return 'Cancelled';
      case 'NO_SHOW':
        return 'No show';
      default:
        return status;
    }
  }
}

/// A single status change in a booking's timeline (backend `StatusEvent`).
class BookingStatusEvent {
  const BookingStatusEvent({
    required this.id,
    required this.bookingId,
    required this.toStatus,
    this.fromStatus,
    this.changedBy,
    this.note = '',
    this.createdAt,
  });

  factory BookingStatusEvent.fromJson(Map<String, dynamic> json) {
    return BookingStatusEvent(
      id: json['id'] as String? ?? '',
      bookingId: json['booking_id'] as String? ?? '',
      fromStatus: json['from_status'] as String?,
      toStatus: json['to_status'] as String? ?? '',
      changedBy: json['changed_by'] as String?,
      note: json['note'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String bookingId;
  final String? fromStatus;
  final String toStatus;
  final String? changedBy;
  final String note;
  final DateTime? createdAt;
}

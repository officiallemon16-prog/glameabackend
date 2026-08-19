/// Admin dashboard counters (backend `admin.Dashboard`).
class AdminDashboard {
  const AdminDashboard({
    this.users = 0,
    this.professionals = 0,
    this.bookings = 0,
    this.completedBookings = 0,
    this.cancelledBookings = 0,
    this.activeDeals = 0,
    this.openDisputes = 0,
    this.pendingPayouts = 0,
    this.totalRevenue = 0,
    this.escrowBalance = 0,
  });

  factory AdminDashboard.fromJson(Map<String, dynamic> json) {
    return AdminDashboard(
      users: (json['users'] as num?)?.toInt() ?? 0,
      professionals: (json['professionals'] as num?)?.toInt() ?? 0,
      bookings: (json['bookings'] as num?)?.toInt() ?? 0,
      completedBookings: (json['completed_bookings'] as num?)?.toInt() ?? 0,
      cancelledBookings: (json['cancelled_bookings'] as num?)?.toInt() ?? 0,
      activeDeals: (json['active_deals'] as num?)?.toInt() ?? 0,
      openDisputes: (json['open_disputes'] as num?)?.toInt() ?? 0,
      pendingPayouts: (json['pending_payouts'] as num?)?.toInt() ?? 0,
      totalRevenue: (json['total_revenue'] as num?)?.toDouble() ?? 0,
      escrowBalance: (json['escrow_balance'] as num?)?.toDouble() ?? 0,
    );
  }

  final int users;
  final int professionals;
  final int bookings;
  final int completedBookings;
  final int cancelledBookings;
  final int activeDeals;
  final int openDisputes;
  final int pendingPayouts;
  final double totalRevenue;
  final double escrowBalance;
}

/// One day of dashboard metrics (backend `admin.DailyMetric`).
class DailyMetric {
  const DailyMetric({this.date = '', this.bookings = 0, this.revenue = 0});

  factory DailyMetric.fromJson(Map<String, dynamic> json) {
    return DailyMetric(
      date: json['date'] as String? ?? '',
      bookings: (json['bookings'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
    );
  }

  final String date;
  final int bookings;
  final double revenue;
}

/// Audit log entry (backend `admin.AuditEntry`).
class AuditEntry {
  const AuditEntry({
    required this.id,
    required this.action,
    required this.entityType,
    this.actorId,
    this.actorRole,
    this.entityId,
    this.beforeState,
    this.afterState,
    this.createdAt,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) {
    return AuditEntry(
      id: json['id'] as String? ?? '',
      actorId: json['actor_id'] as String?,
      actorRole: json['actor_role'] as String?,
      action: json['action'] as String? ?? '',
      entityType: json['entity_type'] as String? ?? '',
      entityId: json['entity_id'] as String?,
      beforeState: json['before_state'] is Map<String, dynamic>
          ? json['before_state'] as Map<String, dynamic>
          : null,
      afterState: json['after_state'] is Map<String, dynamic>
          ? json['after_state'] as Map<String, dynamic>
          : null,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String? actorId;
  final String? actorRole;
  final String action;
  final String entityType;
  final String? entityId;
  final Map<String, dynamic>? beforeState;
  final Map<String, dynamic>? afterState;
  final DateTime? createdAt;
}

/// Analytics summary (backend `analytics.Summary`).
class AnalyticsSummary {
  const AnalyticsSummary({
    this.totalBookings = 0,
    this.completed = 0,
    this.cancelled = 0,
    this.grossRevenue = 0,
    this.platformFees = 0,
    this.payoutsPaid = 0,
    this.avgBookingValue = 0,
    this.conversionRate = 0,
  });

  factory AnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AnalyticsSummary(
      totalBookings: (json['total_bookings'] as num?)?.toInt() ?? 0,
      completed: (json['completed'] as num?)?.toInt() ?? 0,
      cancelled: (json['cancelled'] as num?)?.toInt() ?? 0,
      grossRevenue: (json['gross_revenue'] as num?)?.toDouble() ?? 0,
      platformFees: (json['platform_fees'] as num?)?.toDouble() ?? 0,
      payoutsPaid: (json['payouts_paid'] as num?)?.toDouble() ?? 0,
      avgBookingValue: (json['avg_booking_value'] as num?)?.toDouble() ?? 0,
      conversionRate: (json['conversion_rate'] as num?)?.toDouble() ?? 0,
    );
  }

  final int totalBookings;
  final int completed;
  final int cancelled;
  final double grossRevenue;
  final double platformFees;
  final double payoutsPaid;
  final double avgBookingValue;
  final double conversionRate;
}

/// Daily booking trend (backend `analytics.BookingTrend`).
class BookingTrend {
  const BookingTrend({this.date = '', this.count = 0, this.revenue = 0});

  factory BookingTrend.fromJson(Map<String, dynamic> json) {
    return BookingTrend(
      date: json['date'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
    );
  }

  final String date;
  final int count;
  final double revenue;
}

/// Revenue grouped by service (backend `analytics.ServiceRevenue`).
class ServiceRevenue {
  const ServiceRevenue({
    this.serviceId = '',
    this.name = '',
    this.count = 0,
    this.revenue = 0,
  });

  factory ServiceRevenue.fromJson(Map<String, dynamic> json) {
    return ServiceRevenue(
      serviceId: json['service_id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
    );
  }

  final String serviceId;
  final String name;
  final int count;
  final double revenue;
}

/// Top professional performance (backend `analytics.ProPerformance`).
class ProPerformance {
  const ProPerformance({
    this.professionalId = '',
    this.businessName = '',
    this.bookings = 0,
    this.revenue = 0,
    this.rating = 0,
  });

  factory ProPerformance.fromJson(Map<String, dynamic> json) {
    return ProPerformance(
      professionalId: json['professional_id'] as String? ?? '',
      businessName: json['business_name'] as String? ?? '',
      bookings: (json['bookings'] as num?)?.toInt() ?? 0,
      revenue: (json['revenue'] as num?)?.toDouble() ?? 0,
      rating: (json['rating'] as num?)?.toDouble() ?? 0,
    );
  }

  final String professionalId;
  final String businessName;
  final int bookings;
  final double revenue;
  final double rating;
}

/// Platform setting key/value (backend `platform.Setting`).
class PlatformSetting {
  const PlatformSetting({required this.name, required this.value, this.updatedAt});

  factory PlatformSetting.fromJson(Map<String, dynamic> json) {
    return PlatformSetting(
      name: json['name'] as String? ?? '',
      value: json['value'] as String? ?? '',
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  final String name;
  final String value;
  final DateTime? updatedAt;
}

/// Booking row for admin reports (backend `reports.BookingRow`).
class ReportBookingRow {
  const ReportBookingRow({
    this.id = '',
    this.professional = '',
    this.customer = '',
    this.service = '',
    this.status = '',
    this.totalAmount = 0,
    this.currency = 'NGN',
    this.startAt,
    this.createdAt,
  });

  factory ReportBookingRow.fromJson(Map<String, dynamic> json) {
    return ReportBookingRow(
      id: json['id'] as String? ?? '',
      professional: json['professional'] as String? ?? '',
      customer: json['customer'] as String? ?? '',
      service: json['service'] as String? ?? '',
      status: json['status'] as String? ?? '',
      totalAmount: (json['total_amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'NGN',
      startAt: DateTime.tryParse(json['start_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String professional;
  final String customer;
  final String service;
  final String status;
  final double totalAmount;
  final String currency;
  final DateTime? startAt;
  final DateTime? createdAt;
}

/// Payment row for admin reports (backend `reports.PaymentRow`).
class ReportPaymentRow {
  const ReportPaymentRow({
    this.id = '',
    this.bookingId = '',
    this.amount = 0,
    this.currency = 'NGN',
    this.status = '',
    this.gateway,
    this.createdAt,
  });

  factory ReportPaymentRow.fromJson(Map<String, dynamic> json) {
    return ReportPaymentRow(
      id: json['id'] as String? ?? '',
      bookingId: json['booking_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'NGN',
      status: json['status'] as String? ?? '',
      gateway: json['gateway'] as String?,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String bookingId;
  final double amount;
  final String currency;
  final String status;
  final String? gateway;
  final DateTime? createdAt;
}

/// Payout row for admin reports (backend `reports.PayoutRow`).
class ReportPayoutRow {
  const ReportPayoutRow({
    this.id = '',
    this.professionalId = '',
    this.amount = 0,
    this.currency = 'NGN',
    this.status = '',
    this.paidAt,
    this.createdAt,
  });

  factory ReportPayoutRow.fromJson(Map<String, dynamic> json) {
    return ReportPayoutRow(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'NGN',
      status: json['status'] as String? ?? '',
      paidAt: DateTime.tryParse(json['paid_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String professionalId;
  final double amount;
  final String currency;
  final String status;
  final DateTime? paidAt;
  final DateTime? createdAt;
}

/// Payment intent + wallet models (backend `payments` package).
library;

class PaymentIntent {
  const PaymentIntent({
    required this.id,
    required this.bookingId,
    required this.customerId,
    required this.amountType,
    required this.amount,
    required this.currency,
    required this.status,
    required this.providerCharge,
    required this.platformFee,
    this.gateway,
    this.gatewayReference,
    this.authorizationUrl,
    this.createdAt,
    this.updatedAt,
  });

  factory PaymentIntent.fromJson(Map<String, dynamic> json) {
    return PaymentIntent(
      id: json['id'] as String? ?? '',
      bookingId: json['booking_id'] as String? ?? '',
      customerId: json['customer_id'] as String? ?? '',
      amountType: json['amount_type'] as String? ?? 'DEPOSIT',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'NGN',
      status: json['status'] as String? ?? 'PENDING',
      gateway: json['gateway'] as String?,
      gatewayReference: json['gateway_reference'] as String?,
      authorizationUrl: json['authorization_url'] as String?,
      providerCharge: (json['provider_charge'] as num?)?.toDouble() ?? 0,
      platformFee: (json['platform_fee'] as num?)?.toDouble() ?? 0,
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  final String id;
  final String bookingId;
  final String customerId;
  final String amountType;
  final double amount;
  final String currency;
  final String status;
  final String? gateway;
  final String? gatewayReference;
  final String? authorizationUrl;
  final double providerCharge;
  final double platformFee;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  bool get isPending => status == 'PENDING';
  bool get isSucceeded => status == 'SUCCEEDED';
  bool get isFailed => status == 'FAILED';
  bool get isRefunded => status == 'REFUNDED';
  bool get isCancelled => status == 'CANCELLED';

  bool get isTerminal => isSucceeded || isFailed || isRefunded || isCancelled;

  String get statusLabel {
    switch (status) {
      case 'SUCCEEDED':
        return 'Paid';
      case 'PENDING':
        return 'Awaiting payment';
      case 'FAILED':
        return 'Failed';
      case 'REFUNDED':
        return 'Refunded';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

class PaymentWallet {
  const PaymentWallet({
    required this.userId,
    required this.currency,
    required this.balance,
    this.updatedAt,
  });

  factory PaymentWallet.fromJson(Map<String, dynamic> json) {
    return PaymentWallet(
      userId: json['user_id'] as String? ?? '',
      currency: json['currency'] as String? ?? 'NGN',
      balance: (json['balance'] as num?)?.toDouble() ?? 0,
      updatedAt: DateTime.tryParse(json['updated_at'] as String? ?? ''),
    );
  }

  final String userId;
  final String currency;
  final double balance;
  final DateTime? updatedAt;
}

class LedgerEntry {
  const LedgerEntry({
    required this.id,
    required this.userId,
    required this.type,
    required this.category,
    required this.amount,
    required this.balanceAfter,
    required this.currency,
    required this.reference,
    this.bookingId,
    this.paymentIntentId,
    this.createdAt,
  });

  factory LedgerEntry.fromJson(Map<String, dynamic> json) {
    return LedgerEntry(
      id: json['id'] as String? ?? '',
      userId: json['user_id'] as String? ?? '',
      bookingId: json['booking_id'] as String?,
      paymentIntentId: json['payment_intent_id'] as String?,
      type: json['type'] as String? ?? 'CREDIT',
      category: json['category'] as String? ?? 'ADJUSTMENT',
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      balanceAfter: (json['balance_after'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'NGN',
      reference: json['reference'] as String? ?? '',
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
    );
  }

  final String id;
  final String userId;
  final String? bookingId;
  final String? paymentIntentId;
  final String type;
  final String category;
  final double amount;
  final double balanceAfter;
  final String currency;
  final String reference;
  final DateTime? createdAt;

  bool get isCredit => type == 'CREDIT';

  String get categoryLabel {
    switch (category) {
      case 'DEPOSIT':
        return 'Deposit';
      case 'BALANCE_PAYMENT':
        return 'Balance payment';
      case 'FULL_PAYMENT':
        return 'Full payment';
      case 'REFUND':
        return 'Refund';
      case 'EARNING':
        return 'Earnings';
      case 'PLATFORM_FEE':
        return 'Platform fee';
      case 'PAYOUT':
        return 'Payout';
      default:
        return 'Adjustment';
    }
  }
}

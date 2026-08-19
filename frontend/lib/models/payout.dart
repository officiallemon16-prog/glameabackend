/// Payout bank account (backend `payouts.PayoutAccount`).
class PayoutAccount {
  const PayoutAccount({
    required this.id,
    required this.professionalId,
    required this.bankName,
    this.bankCode = '',
    required this.accountNumber,
    required this.accountName,
    this.isVerified = false,
    this.isDefault = false,
  });

  factory PayoutAccount.fromJson(Map<String, dynamic> json) {
    return PayoutAccount(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      bankName: json['bank_name'] as String? ?? '',
      bankCode: json['bank_code'] as String? ?? '',
      accountNumber: json['account_number'] as String? ?? '',
      accountName: json['account_name'] as String? ?? '',
      isVerified: json['is_verified'] as bool? ?? false,
      isDefault: json['is_default'] as bool? ?? false,
    );
  }

  final String id;
  final String professionalId;
  final String bankName;
  final String bankCode;
  final String accountNumber;
  final String accountName;
  final bool isVerified;
  final bool isDefault;

  String get maskedNumber {
    if (accountNumber.length <= 4) return accountNumber;
    return '•••• ${accountNumber.substring(accountNumber.length - 4)}';
  }
}

/// Payout request (backend `payouts.Payout`).
class Payout {
  const Payout({
    required this.id,
    required this.professionalId,
    this.payoutAccountId,
    this.amount = 0,
    this.currency = 'NGN',
    this.status = 'PENDING',
    this.note = '',
    this.gatewayReference = '',
    this.paidAt,
    this.createdAt,
    this.professionalName = '',
    this.accountName = '',
    this.bankName = '',
  });

  factory Payout.fromJson(Map<String, dynamic> json) {
    return Payout(
      id: json['id'] as String? ?? '',
      professionalId: json['professional_id'] as String? ?? '',
      payoutAccountId: json['payout_account_id'] as String?,
      amount: (json['amount'] as num?)?.toDouble() ?? 0,
      currency: json['currency'] as String? ?? 'NGN',
      status: json['status'] as String? ?? 'PENDING',
      note: json['note'] as String? ?? '',
      gatewayReference: json['gateway_reference'] as String? ?? '',
      paidAt: DateTime.tryParse(json['paid_at'] as String? ?? ''),
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? ''),
      professionalName: json['professional_name'] as String? ?? '',
      accountName: json['account_name'] as String? ?? '',
      bankName: json['bank_name'] as String? ?? '',
    );
  }

  final String id;
  final String professionalId;
  final String? payoutAccountId;
  final double amount;
  final String currency;
  final String status;
  final String note;
  final String gatewayReference;
  final DateTime? paidAt;
  final DateTime? createdAt;
  final String professionalName;
  final String accountName;
  final String bankName;

  String get statusLabel {
    switch (status) {
      case 'PENDING':
        return 'Pending';
      case 'PAID':
        return 'Paid';
      case 'FAILED':
        return 'Failed';
      case 'CANCELLED':
        return 'Cancelled';
      default:
        return status;
    }
  }
}

/// Professional payout balance (backend `payouts.Balance`).
class PayoutBalance {
  const PayoutBalance({
    this.available = 0,
    this.pending = 0,
    this.total = 0,
  });

  factory PayoutBalance.fromJson(Map<String, dynamic> json) {
    return PayoutBalance(
      available: (json['available_balance'] as num?)?.toDouble() ?? 0,
      pending: (json['pending_balance'] as num?)?.toDouble() ?? 0,
      total: (json['total_balance'] as num?)?.toDouble() ?? 0,
    );
  }

  final double available;
  final double pending;
  final double total;
}

/// Professional earnings snapshot (backend `payouts.EarningsSummary`).
class EarningsSummary {
  const EarningsSummary({
    this.currency = 'NGN',
    this.totalEarned = 0,
    this.available = 0,
    this.pending = 0,
    this.walletBalance = 0,
    this.thisWeek = 0,
    this.thisMonth = 0,
  });

  factory EarningsSummary.fromJson(Map<String, dynamic> json) {
    return EarningsSummary(
      currency: json['currency'] as String? ?? 'NGN',
      totalEarned: (json['total_earned'] as num?)?.toDouble() ?? 0,
      available: (json['available'] as num?)?.toDouble() ?? 0,
      pending: (json['pending'] as num?)?.toDouble() ?? 0,
      walletBalance: (json['wallet_balance'] as num?)?.toDouble() ?? 0,
      thisWeek: (json['this_week'] as num?)?.toDouble() ?? 0,
      thisMonth: (json['this_month'] as num?)?.toDouble() ?? 0,
    );
  }

  final String currency;
  final double totalEarned;
  final double available;
  final double pending;
  final double walletBalance;
  final double thisWeek;
  final double thisMonth;
}

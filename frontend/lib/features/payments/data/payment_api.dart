import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/payment.dart';

/// Payment endpoints (spec section 17 PAYMENT & WALLET).
/// All calls are routed through [_guard] so failures surface as [AppException].
class PaymentApi {
  PaymentApi(this._dio);

  final Dio _dio;

  /// Creates (or returns the existing) payment intent for a booking.
  /// amountType is DEPOSIT | BALANCE | FULL.
  Future<PaymentIntent> createIntent({
    required String bookingId,
    String amountType = 'DEPOSIT',
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/payments/intents',
        data: {'booking_id': bookingId, 'amount_type': amountType},
      );
      final data = _data(res.data);
      return PaymentIntent.fromJson(
        data['intent'] as Map<String, dynamic>? ?? const {},
      );
    });
  }

  /// Latest state of an intent by id (used to poll after checkout).
  Future<PaymentIntent> fetchIntent(String id) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/payments/intents/$id');
      final data = _data(res.data);
      return PaymentIntent.fromJson(
        data['intent'] as Map<String, dynamic>? ?? const {},
      );
    });
  }

  /// The existing DEPOSIT intent for a booking, or null when the deposit has
  /// not been created yet. Read-only - never creates an intent.
  Future<PaymentIntent?> fetchDepositIntentForBooking(String bookingId) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/payments/intents/by-booking/$bookingId',
      );
      final data = _data(res.data);
      final intent = data['intent'];
      if (intent is Map<String, dynamic>) return PaymentIntent.fromJson(intent);
      return null;
    });
  }

  Future<PaymentWallet> fetchWallet() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/payments/wallet');
      final data = _data(res.data);
      return PaymentWallet.fromJson(
        data['wallet'] as Map<String, dynamic>? ?? const {},
      );
    });
  }

  Future<({List<LedgerEntry> items, int total})> fetchTransactions({
    int limit = 50,
    int offset = 0,
  }) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/payments/transactions',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return (
        items: [
          for (final item in data['transactions'] as List? ?? const [])
            if (item is Map<String, dynamic>) LedgerEntry.fromJson(item),
        ],
        total: (data['total'] as num?)?.toInt() ?? 0,
      );
    });
  }

  Map<String, dynamic> _data(Map<String, dynamic>? body) {
    final data = body?['data'];
    return data is Map<String, dynamic> ? data : const {};
  }

  Future<T> _guard<T>(Future<T> Function() run) async {
    try {
      return await run();
    } catch (e) {
      throw mapError(e);
    }
  }
}

final paymentApiProvider = Provider<PaymentApi>((ref) => PaymentApi(ref.watch(apiClientProvider)));

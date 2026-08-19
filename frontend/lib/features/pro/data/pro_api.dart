import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/availability.dart';
import '../../../models/beauty_service.dart';
import '../../../models/booking.dart';
import '../../../models/deal.dart';
import '../../../models/payout.dart';
import '../../../models/portfolio_item.dart';
import '../../../models/professional.dart';
import '../../../models/review.dart';
import '../../../models/verification.dart';

/// Professional-facing endpoints. All calls route through [_guard] so
/// failures surface as [AppException].
class ProApi {
  ProApi(this._dio);

  final Dio _dio;

  // -------------------------------------------------------------------------
  // Profile
  // -------------------------------------------------------------------------

  Future<Professional> fetchMyProfile() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/professionals/me');
      final data = _data(res.data);
      return Professional.fromJson(data['professional'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<Professional> updateMyProfile(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/professionals/me',
        data: payload,
      );
      final data = _data(res.data);
      return Professional.fromJson(data['professional'] as Map<String, dynamic>? ?? const {});
    });
  }

  /// Creates the professional profile (POST /professionals). Only valid for
  /// PROFESSIONAL accounts that have no profile yet.
  Future<Professional> createMyProfile(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professionals',
        data: payload,
      );
      final data = _data(res.data);
      return Professional.fromJson(data['professional'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Bookings
  // -------------------------------------------------------------------------

  Future<List<Booking>> fetchProBookings({int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professionals/me/bookings',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return [
        for (final item in data['bookings'] as List? ?? const [])
          if (item is Map<String, dynamic>) Booking.fromJson(item),
      ];
    });
  }

  Future<Booking> confirmBooking(String id) =>
      _bookingAction(id, 'confirm');

  Future<Booking> startBooking(String id) =>
      _bookingAction(id, 'start');

  Future<Booking> completeBooking(String id) =>
      _bookingAction(id, 'complete');

  Future<Booking> _bookingAction(String id, String action) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professionals/me/bookings/$id/$action',
      );
      final data = _data(res.data);
      return Booking.fromJson(data['booking'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Services
  // -------------------------------------------------------------------------

  Future<List<BeautyService>> fetchMyServices() {
    return _guard(() async {
      final pro = await fetchMyProfile();
      final res = await _dio.get<Map<String, dynamic>>(
        '/services',
        queryParameters: {'professional_id': pro.id, 'per_page': 100},
      );
      final data = _data(res.data);
      return [
        for (final item in data['services'] as List? ?? const [])
          if (item is Map<String, dynamic>) BeautyService.fromJson(item),
      ];
    });
  }

  Future<BeautyService> createService(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>('/services', data: payload);
      final data = _data(res.data);
      return BeautyService.fromJson(data['service'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<BeautyService> updateService(String id, Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.patch<Map<String, dynamic>>('/services/$id', data: payload);
      final data = _data(res.data);
      return BeautyService.fromJson(data['service'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<void> deleteService(String id) async {
    await _guard(() async {
      await _dio.delete('/services/$id');
      return true;
    });
  }

  // -------------------------------------------------------------------------
  // Availability
  // -------------------------------------------------------------------------

  Future<List<AvailabilityWindow>> fetchWindows() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/availability/windows');
      final data = _data(res.data);
      return [
        for (final item in data['windows'] as List? ?? const [])
          if (item is Map<String, dynamic>) AvailabilityWindow.fromJson(item),
      ];
    });
  }

  Future<List<AvailabilityWindow>> saveWindows(List<Map<String, dynamic>> windows) {
    return _guard(() async {
      final res = await _dio.put<Map<String, dynamic>>(
        '/availability/windows',
        data: {'windows': windows},
      );
      final data = _data(res.data);
      return [
        for (final item in data['windows'] as List? ?? const [])
          if (item is Map<String, dynamic>) AvailabilityWindow.fromJson(item),
      ];
    });
  }

  Future<List<AvailabilityException>> fetchExceptions({String? from}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/availability/exceptions',
        queryParameters: {if (from != null) 'from': from},
      );
      final data = _data(res.data);
      return [
        for (final item in data['exceptions'] as List? ?? const [])
          if (item is Map<String, dynamic>) AvailabilityException.fromJson(item),
      ];
    });
  }

  Future<AvailabilityException> addException(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>('/availability/exceptions', data: payload);
      final data = _data(res.data);
      return AvailabilityException.fromJson(data['exception'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<void> deleteException(String id) async {
    await _guard(() async {
      await _dio.delete('/availability/exceptions/$id');
      return true;
    });
  }

  // -------------------------------------------------------------------------
  // Portfolio
  // -------------------------------------------------------------------------

  Future<List<PortfolioItem>> fetchMyPortfolio() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/portfolio/me');
      final data = _data(res.data);
      return [
        for (final item in data['items'] as List? ?? const [])
          if (item is Map<String, dynamic>) PortfolioItem.fromJson(item),
      ];
    });
  }

  Future<PortfolioItem> createPortfolioItem(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>('/portfolio', data: payload);
      final data = _data(res.data);
      return PortfolioItem.fromJson(data['item'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<PortfolioItem> updatePortfolioItem(String id, Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.patch<Map<String, dynamic>>('/portfolio/$id', data: payload);
      final data = _data(res.data);
      return PortfolioItem.fromJson(data['item'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<void> deletePortfolioItem(String id) async {
    await _guard(() async {
      await _dio.delete('/portfolio/$id');
      return true;
    });
  }

  // -------------------------------------------------------------------------
  // Deals
  // -------------------------------------------------------------------------

  Future<List<Deal>> fetchMyDeals({int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professionals/me/deals',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return [
        for (final item in data['deals'] as List? ?? const [])
          if (item is Map<String, dynamic>) Deal.fromJson(item),
      ];
    });
  }

  Future<Deal> createDeal(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>('/professionals/me/deals', data: payload);
      final data = _data(res.data);
      return Deal.fromJson(data['deal'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<Deal> updateDeal(String id, Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.patch<Map<String, dynamic>>('/professionals/me/deals/$id', data: payload);
      final data = _data(res.data);
      return Deal.fromJson(data['deal'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<void> deactivateDeal(String id) async {
    await _guard(() async {
      await _dio.delete('/professionals/me/deals/$id');
      return true;
    });
  }

  // -------------------------------------------------------------------------
  // Reviews
  // -------------------------------------------------------------------------

  Future<List<Review>> fetchProReviews({int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professionals/me/reviews',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return [
        for (final item in data['reviews'] as List? ?? const [])
          if (item is Map<String, dynamic>) Review.fromJson(item),
      ];
    });
  }

  Future<Review> respondToReview(String id, String response) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/professionals/me/reviews/$id/respond',
        data: {'response': response},
      );
      final data = _data(res.data);
      return Review.fromJson(data['review'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Verification
  // -------------------------------------------------------------------------

  Future<List<VerificationDocument>> fetchVerificationDocs() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/verification/me');
      final data = _data(res.data);
      return [
        for (final item in data['documents'] as List? ?? const [])
          if (item is Map<String, dynamic>) VerificationDocument.fromJson(item),
      ];
    });
  }

  Future<VerificationDocument> submitVerificationDoc(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>('/verification/documents', data: payload);
      final data = _data(res.data);
      return VerificationDocument.fromJson(data['document'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Payouts
  // -------------------------------------------------------------------------

  Future<List<PayoutAccount>> fetchAccounts() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/payouts/accounts');
      final data = _data(res.data);
      return [
        for (final item in data['accounts'] as List? ?? const [])
          if (item is Map<String, dynamic>) PayoutAccount.fromJson(item),
      ];
    });
  }

  Future<PayoutAccount> addAccount(Map<String, dynamic> payload) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>('/payouts/accounts', data: payload);
      final data = _data(res.data);
      return PayoutAccount.fromJson(data['account'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<void> setDefaultAccount(String id) async {
    await _guard(() async {
      await _dio.post('/payouts/accounts/$id/default');
      return true;
    });
  }

  Future<void> deleteAccount(String id) async {
    await _guard(() async {
      await _dio.delete('/payouts/accounts/$id');
      return true;
    });
  }

  Future<List<Payout>> fetchPayoutRequests({int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/payouts/requests',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return [
        for (final item in data['payouts'] as List? ?? const [])
          if (item is Map<String, dynamic>) Payout.fromJson(item),
      ];
    });
  }

  Future<Payout> requestPayout({required double amount, String? accountId, String note = ''}) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/payouts/requests',
        data: {
          'amount': amount,
          if (accountId != null && accountId.isNotEmpty) 'account_id': accountId,
          'note': note,
        },
      );
      final data = _data(res.data);
      return Payout.fromJson(data['payout'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<PayoutBalance> fetchBalance() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/payouts/balance');
      final data = _data(res.data);
      return PayoutBalance.fromJson(data);
    });
  }

  Future<EarningsSummary> fetchEarnings() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/payouts/earnings');
      final data = _data(res.data);
      return EarningsSummary.fromJson(
          data['earnings'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------------------

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

final proApiProvider = Provider<ProApi>((ref) => ProApi(ref.watch(apiClientProvider)));

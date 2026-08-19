import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../models/admin_models.dart';
import '../../../models/deal.dart';
import '../../../models/dispute.dart';
import '../../../models/payout.dart';
import '../../../models/professional.dart';
import '../../../models/user.dart';
import '../../../models/verification.dart';

/// Admin-facing endpoints. All calls route through [_guard] so failures
/// surface as [AppException].
class AdminApi {
  AdminApi(this._dio);

  final Dio _dio;

  // -------------------------------------------------------------------------
  // Dashboard & metrics
  // -------------------------------------------------------------------------

  Future<AdminDashboard> fetchDashboard() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/admin/dashboard');
      return AdminDashboard.fromJson(_data(res.data));
    });
  }

  Future<List<DailyMetric>> fetchDailyMetrics({String? from, String? to}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/dashboard/metrics',
        queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to},
      );
      final data = _data(res.data);
      return [
        for (final item in data['metrics'] as List? ?? const [])
          if (item is Map<String, dynamic>) DailyMetric.fromJson(item),
      ];
    });
  }

  // -------------------------------------------------------------------------
  // Users
  // -------------------------------------------------------------------------

  Future<(List<User>, int)> fetchUsers({int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/users',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['users'] as List? ?? const [])
          if (item is Map<String, dynamic>) User.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
    });
  }

  Future<void> setUserStatus(String id, String status) async {
    await _guard(() async {
      await _dio.patch('/admin/users/$id/status', data: {'status': status});
      return true;
    });
  }

  Future<void> setUserRole(String id, String role) async {
    await _guard(() async {
      await _dio.patch('/admin/users/$id/role', data: {'role': role});
      return true;
    });
  }

  // -------------------------------------------------------------------------
  // Professionals
  // -------------------------------------------------------------------------

  Future<(List<Professional>, int)> fetchProfessionals({String? status, int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/professionals',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['professionals'] as List? ?? const [])
          if (item is Map<String, dynamic>) Professional.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
    });
  }

  Future<void> setProfessionalStatus(String id, String status) async {
    await _guard(() async {
      await _dio.patch('/admin/professionals/$id/status', data: {'status': status});
      return true;
    });
  }

  // -------------------------------------------------------------------------
  // Verification
  // -------------------------------------------------------------------------

  Future<List<VerificationDocument>> fetchVerificationDocuments({bool pendingOnly = false}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/verification/documents',
        queryParameters: {if (pendingOnly) 'pending': 'true'},
      );
      final data = _data(res.data);
      return [
        for (final item in data['documents'] as List? ?? const [])
          if (item is Map<String, dynamic>) VerificationDocument.fromJson(item),
      ];
    });
  }

  Future<VerificationDocument> reviewDocument(String id, {required bool approve, String note = ''}) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/admin/verification/documents/$id/review',
        data: {'approve': approve, 'note': note},
      );
      final data = _data(res.data);
      return VerificationDocument.fromJson(data['document'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Disputes
  // -------------------------------------------------------------------------

  Future<(List<Dispute>, int)> fetchDisputes({String? status, int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/disputes',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['disputes'] as List? ?? const [])
          if (item is Map<String, dynamic>) Dispute.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
    });
  }

  Future<Dispute> resolveDispute(String id, String resolution) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/admin/disputes/$id/resolve',
        data: {'resolution': resolution},
      );
      final data = _data(res.data);
      return Dispute.fromJson(data['dispute'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Deals
  // -------------------------------------------------------------------------

  Future<(List<Deal>, int)> fetchAllDeals({bool? active, int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/deals',
        queryParameters: {
          if (active != null) 'active': active.toString(),
          'limit': limit,
          'offset': offset,
        },
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['deals'] as List? ?? const [])
          if (item is Map<String, dynamic>) Deal.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
    });
  }

  Future<Deal> toggleDeal(String id, bool active) {
    return _guard(() async {
      final res = await _dio.patch<Map<String, dynamic>>(
        '/admin/deals/$id/toggle',
        data: {'active': active},
      );
      final data = _data(res.data);
      return Deal.fromJson(data['deal'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Payouts
  // -------------------------------------------------------------------------

  Future<(List<Payout>, int)> fetchPayouts({String? status, int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/payouts',
        queryParameters: {
          if (status != null && status.isNotEmpty) 'status': status,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['payouts'] as List? ?? const [])
          if (item is Map<String, dynamic>) Payout.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
    });
  }

  Future<Payout> payPayout(String id) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>('/admin/payouts/$id/pay');
      final data = _data(res.data);
      return Payout.fromJson(data['payout'] as Map<String, dynamic>? ?? const {});
    });
  }

  // -------------------------------------------------------------------------
  // Reports
  // -------------------------------------------------------------------------

  Future<(List<ReportBookingRow>, int)> fetchBookingReport({String? from, String? to, int limit = 200, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/reports/bookings',
        queryParameters: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['bookings'] as List? ?? const [])
          if (item is Map<String, dynamic>) ReportBookingRow.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
    });
  }

  Future<(List<ReportPaymentRow>, int)> fetchPaymentReport({String? from, String? to, int limit = 200, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/reports/payments',
        queryParameters: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['payments'] as List? ?? const [])
          if (item is Map<String, dynamic>) ReportPaymentRow.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
    });
  }

  Future<(List<ReportPayoutRow>, int)> fetchPayoutReport({String? from, String? to, int limit = 200, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/reports/payouts',
        queryParameters: {
          if (from != null) 'from': from,
          if (to != null) 'to': to,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['payouts'] as List? ?? const [])
          if (item is Map<String, dynamic>) ReportPayoutRow.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
    });
  }

  // -------------------------------------------------------------------------
  // Analytics
  // -------------------------------------------------------------------------

  Future<AnalyticsSummary> fetchAnalyticsSummary({String? from, String? to}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/analytics/summary',
        queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to},
      );
      return AnalyticsSummary.fromJson(_data(res.data));
    });
  }

  Future<List<BookingTrend>> fetchBookingTrends({String? from, String? to}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/analytics/trends',
        queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to},
      );
      final data = _data(res.data);
      return [
        for (final item in data['trends'] as List? ?? const [])
          if (item is Map<String, dynamic>) BookingTrend.fromJson(item),
      ];
    });
  }

  Future<List<ServiceRevenue>> fetchRevenueByService({String? from, String? to}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/analytics/revenue-by-service',
        queryParameters: {if (from != null) 'from': from, if (to != null) 'to': to},
      );
      final data = _data(res.data);
      return [
        for (final item in data['services'] as List? ?? const [])
          if (item is Map<String, dynamic>) ServiceRevenue.fromJson(item),
      ];
    });
  }

  Future<List<ProPerformance>> fetchTopProfessionals({int limit = 10}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/analytics/top-professionals',
        queryParameters: {'limit': limit},
      );
      final data = _data(res.data);
      return [
        for (final item in data['professionals'] as List? ?? const [])
          if (item is Map<String, dynamic>) ProPerformance.fromJson(item),
      ];
    });
  }

  // -------------------------------------------------------------------------
  // Settings & audit
  // -------------------------------------------------------------------------

  Future<List<PlatformSetting>> fetchSettings() {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/admin/settings');
      final data = _data(res.data);
      return [
        for (final item in data['settings'] as List? ?? const [])
          if (item is Map<String, dynamic>) PlatformSetting.fromJson(item),
      ];
    });
  }

  Future<void> updateSettings(Map<String, String> pairs) async {
    await _guard(() async {
      await _dio.patch('/admin/settings', data: pairs);
      return true;
    });
  }

  Future<(List<AuditEntry>, int)> fetchAuditLogs({String? entityType, String? entityId, int limit = 100, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/admin/audit-logs',
        queryParameters: {
          if (entityType != null && entityType.isNotEmpty) 'entity_type': entityType,
          if (entityId != null && entityId.isNotEmpty) 'entity_id': entityId,
          'limit': limit,
          'offset': offset,
        },
      );
      final data = _data(res.data);
      final items = [
        for (final item in data['audit_logs'] as List? ?? const [])
          if (item is Map<String, dynamic>) AuditEntry.fromJson(item),
      ];
      final total = (data['total'] as num?)?.toInt() ?? items.length;
      return (items, total);
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

final adminApiProvider = Provider<AdminApi>((ref) => AdminApi(ref.watch(apiClientProvider)));

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_exception.dart';
import '../../../core/network/api_client.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/booking.dart';
import '../../../models/slot.dart';

/// Booking + availability endpoints (spec section 11 BOOKING).
/// All calls are routed through [_guard] so failures surface as [AppException].
class BookingApi {
  BookingApi(this._dio);

  final Dio _dio;

  Future<List<AvailabilitySlot>> fetchSlots(
    String professionalId, {
    required DateTime date,
    required int durationMinutes,
  }) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/professionals/$professionalId/availability/slots',
        queryParameters: {
          'date': Formatters.apiDate(date),
          'duration_minutes': durationMinutes,
        },
      );
      final data = _data(res.data);
      return [
        for (final item in data['slots'] as List? ?? const [])
          if (item is Map<String, dynamic>) AvailabilitySlot.fromJson(item),
      ];
    });
  }

  Future<Booking> createBooking({
    required String serviceId,
    required DateTime startAt,
    bool homeService = false,
    double? locationLat,
    double? locationLng,
    String locationAddress = '',
    String customerNotes = '',
    String? idempotencyKey,
  }) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/bookings',
        data: {
          'service_id': serviceId,
          'start_at': startAt.toUtc().toIso8601String(),
          'home_service': homeService,
          if (locationLat != null) 'location_lat': locationLat,
          if (locationLng != null) 'location_lng': locationLng,
          'location_address': locationAddress,
          'customer_notes': customerNotes,
        },
        options: Options(
          headers: {
            if (idempotencyKey != null && idempotencyKey.isNotEmpty)
              'Idempotency-Key': idempotencyKey,
          },
        ),
      );
      final data = _data(res.data);
      return Booking.fromJson(data['booking'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<List<Booking>> fetchMyBookings({int limit = 50, int offset = 0}) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>(
        '/bookings/me',
        queryParameters: {'limit': limit, 'offset': offset},
      );
      final data = _data(res.data);
      return [
        for (final item in data['bookings'] as List? ?? const [])
          if (item is Map<String, dynamic>) Booking.fromJson(item),
      ];
    });
  }

  Future<Booking> fetchBooking(String id) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/bookings/$id');
      final data = _data(res.data);
      return Booking.fromJson(data['booking'] as Map<String, dynamic>? ?? const {});
    });
  }
  Future<Booking> cancelBooking(String id, String reason) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/bookings/$id/cancel',
        data: {'reason': reason},
      );
      final data = _data(res.data);
      return Booking.fromJson(data['booking'] as Map<String, dynamic>? ?? const {});
    });
  }

  Future<List<BookingStatusEvent>> fetchHistory(String id) {
    return _guard(() async {
      final res = await _dio.get<Map<String, dynamic>>('/bookings/$id/history');
      final data = _data(res.data);
      return [
        for (final item in data['events'] as List? ?? const [])
          if (item is Map<String, dynamic>) BookingStatusEvent.fromJson(item),
      ];
    });
  }

  Future<Booking> rescheduleBooking(String id, DateTime startAt) {
    return _guard(() async {
      final res = await _dio.post<Map<String, dynamic>>(
        '/bookings/$id/reschedule',
        data: {'start_at': startAt.toUtc().toIso8601String()},
      );
      final data = _data(res.data);
      return Booking.fromJson(data['booking'] as Map<String, dynamic>? ?? const {});
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

final bookingApiProvider = Provider<BookingApi>((ref) => BookingApi(ref.watch(apiClientProvider)));

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/core/utils/formatters.dart';
import 'package:glamea/features/booking/booking_controller.dart';
import 'package:glamea/features/booking/data/booking_api.dart';
import 'package:glamea/models/beauty_service.dart';
import 'package:glamea/models/booking.dart';
import 'package:glamea/models/professional.dart';
import 'package:glamea/models/slot.dart';

class FakeBookingApi extends BookingApi {
  FakeBookingApi() : super(Dio());

  final List<DateTime> slotDates = [];
  String? lastServiceId;
  String? lastIdempotencyKey;
  bool lastHomeService = false;
  String lastNotes = '';

  @override
  Future<List<AvailabilitySlot>> fetchSlots(
    String professionalId, {
    required DateTime date,
    required int durationMinutes,
  }) async {
    slotDates.add(date);
    return [
      AvailabilitySlot(
        start: DateTime(2026, 8, 14, 9),
        end: DateTime(2026, 8, 14, 10),
      ),
      AvailabilitySlot(
        start: DateTime(2026, 8, 14, 10),
        end: DateTime(2026, 8, 14, 11),
      ),
    ];
  }

  @override
  Future<Booking> createBooking({
    required String serviceId,
    required DateTime startAt,
    bool homeService = false,
    double? locationLat,
    double? locationLng,
    String locationAddress = '',
    String customerNotes = '',
    String? idempotencyKey,
  }) async {
    lastServiceId = serviceId;
    lastHomeService = homeService;
    lastNotes = customerNotes;
    lastIdempotencyKey = idempotencyKey;
    return Booking(
      id: 'b-1',
      professionalId: 'pro-1',
      customerId: 'u-1',
      serviceId: serviceId,
      status: 'PENDING',
      startAt: startAt,
      endAt: startAt.add(const Duration(hours: 1)),
      baseAmount: 1000,
      totalAmount: 1000,
      depositAmount: 100,
      balanceAmount: 900,
      currency: 'NGN',
      homeService: homeService,
      serviceName: 'Sweep',
      professionalName: "Ada's Beauty Studio",
    );
  }
}

const service = BeautyService(
  id: 's-1',
  professionalId: 'pro-1',
  name: 'Sweep',
  basePrice: 1000,
  currency: 'NGN',
  durationMinutes: 60,
  depositPercentage: 10,
  homeServiceAvailable: true,
);

const professional = Professional(
  id: 'pro-1',
  userId: 'u-1',
  businessName: "Ada's Beauty Studio",
  homeServiceEnabled: true,
);

void main() {
  group('AvailabilitySlot', () {
    test('parses start and end', () {
      final slot = AvailabilitySlot.fromJson(const {
        'start': '2026-08-14T09:00:00+01:00',
        'end': '2026-08-14T10:00:00+01:00',
      });

      expect(slot.start.isUtc, isTrue);
      expect(slot.end.toUtc().hour, 9);
      expect(slot.end.toUtc().isAfter(slot.start.toUtc()), isTrue);
    });
  });

  group('Booking', () {
    const bookingJson = {
      'id': 'b-1',
      'professional_id': 'pro-1',
      'customer_id': 'c-1',
      'service_id': 's-1',
      'status': 'CONFIRMED',
      'start_at': '2026-08-14T09:00:00+01:00',
      'end_at': '2026-08-14T10:00:00+01:00',
      'base_amount': 1000,
      'total_amount': 1000,
      'deposit_amount': 100,
      'currency': 'NGN',
      'home_service': true,
      'location_address': '12 Marina, Lagos',
      'customer_notes': 'Ring the bell',
      'service_name': 'Sweep',
      'professional_name': "Ada's Beauty Studio",
      'customer_name': 'Amina Bello',
    };

    test('parses full payload and derives helpers', () {
      final booking = Booking.fromJson(bookingJson);

      expect(booking.id, 'b-1');
      expect(booking.status, 'CONFIRMED');
      expect(booking.isConfirmed, isTrue);
      expect(booking.isUpcoming, isTrue);
      expect(booking.cancellable, isTrue);
      expect(booking.homeService, isTrue);
      expect(booking.locationAddress, '12 Marina, Lagos');
      expect(booking.serviceName, 'Sweep');
      expect(booking.balanceAmount, 900);
      expect(booking.statusLabel, 'Confirmed');
    });

    test('cancelled bookings are not cancellable', () {
      final booking = Booking.fromJson({...bookingJson, 'status': 'CANCELLED'});

      expect(booking.isCancelled, isTrue);
      expect(booking.isUpcoming, isFalse);
      expect(booking.cancellable, isFalse);
      expect(booking.statusLabel, 'Cancelled');
    });

    test('missing fields fall back safely', () {
      final booking = Booking.fromJson(const {
        'id': 'b-2',
        'professional_id': 'pro-1',
        'customer_id': 'c-1',
        'service_id': 's-1',
      });

      expect(booking.status, 'PENDING');
      expect(booking.baseAmount, 0);
      expect(booking.currency, 'NGN');
      expect(booking.startAt, isNull);
      expect(booking.serviceName, isEmpty);
    });
  });

  group('BookingStatusEvent', () {
    test('parses event payload', () {
      final event = BookingStatusEvent.fromJson(const {
        'id': 'e-1',
        'booking_id': 'b-1',
        'from_status': 'PENDING',
        'to_status': 'CONFIRMED',
        'note': 'Artist confirmed',
        'created_at': '2026-08-13T12:00:00Z',
      });

      expect(event.bookingId, 'b-1');
      expect(event.toStatus, 'CONFIRMED');
      expect(event.note, 'Artist confirmed');
      expect(event.createdAt, isNotNull);
    });
  });

  group('BookingFlowController', () {
    test('selecting a date loads slots and picking a slot enables submit', () async {
      final container = ProviderContainer(
        overrides: [bookingApiProvider.overrideWithValue(FakeBookingApi())],
      );
      addTearDown(container.dispose);

      const args = BookingFlowArgs(service: service, professional: professional);
      final notifier = container.read(bookingFlowProvider(args).notifier);

      expect(container.read(bookingFlowProvider(args)).idempotencyKey, isNotNull);

      final date = DateTime(2026, 8, 14);
      notifier.selectDate(date);
      await Future<void>.delayed(Duration.zero);

      final state = container.read(bookingFlowProvider(args));
      expect(state.slotStatus, SlotLoadStatus.ready);
      expect(state.slots, hasLength(2));

      notifier.selectSlot(state.slots.first.start);
      expect(container.read(bookingFlowProvider(args)).readyToSubmit, isTrue);
    });

    test('submit creates a booking with the idempotency key', () async {
      final api = FakeBookingApi();
      final container = ProviderContainer(overrides: [bookingApiProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);

      const args = BookingFlowArgs(service: service, professional: professional);
      final notifier = container.read(bookingFlowProvider(args).notifier);
      final idem = container.read(bookingFlowProvider(args)).idempotencyKey;

      notifier.selectDate(DateTime(2026, 8, 14));
      await Future<void>.delayed(Duration.zero);
      final slotStart = container.read(bookingFlowProvider(args)).slots.first.start;
      notifier.selectSlot(slotStart);
      notifier.setHomeService(true);
      notifier.setNotes('Ring the bell');

      await notifier.submit();

      final state = container.read(bookingFlowProvider(args));
      expect(state.createdBooking, isNotNull);
      expect(state.createdBooking!.id, 'b-1');
      expect(api.lastServiceId, 's-1');
      expect(api.lastHomeService, isTrue);
      expect(api.lastNotes, 'Ring the bell');
      expect(api.lastIdempotencyKey, idem);
    });

    test('submit does nothing without a selected slot', () async {
      final api = FakeBookingApi();
      final container = ProviderContainer(overrides: [bookingApiProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);

      const args = BookingFlowArgs(service: service, professional: professional);
      final notifier = container.read(bookingFlowProvider(args).notifier);

      await notifier.submit();

      expect(api.lastServiceId, isNull);
      expect(container.read(bookingFlowProvider(args)).createdBooking, isNull);
    });
  });

  group('Formatters', () {
    test('apiDate produces YYYY-MM-DD', () {
      expect(Formatters.apiDate(DateTime(2026, 8, 14)), '2026-08-14');
    });

    test('time formats 12-hour clock', () {
      expect(Formatters.time(DateTime(2026, 8, 14, 9, 30)), '9:30 AM');
      expect(Formatters.time(DateTime(2026, 8, 14, 18, 0)), '6:00 PM');
    });
  });
}

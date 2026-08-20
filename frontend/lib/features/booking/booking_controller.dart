import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/beauty_service.dart';
import '../../models/booking.dart';
import '../../models/professional.dart';
import '../../models/slot.dart';
import 'data/booking_api.dart';

/// Payload used to open the booking flow for a specific service.
class BookingFlowArgs {
  const BookingFlowArgs({required this.service, required this.professional});

  final BeautyService service;
  final Professional professional;
}

enum SlotLoadStatus { idle, loading, ready, error }

enum BookingFlowStep { details, payment }

/// State of the multi-step booking wizard.
class BookingFlowState {
  const BookingFlowState({
    required this.service,
    required this.professional,
    this.selectedDate,
    this.slotStatus = SlotLoadStatus.idle,
    this.slots = const [],
    this.slotError,
    this.selectedStart,
    this.homeService = false,
    this.address = '',
    this.notes = '',
    this.submitting = false,
    this.error,
    this.createdBooking,
    this.idempotencyKey,
    this.step = BookingFlowStep.details,
    this.paymentHandled = false,
  });

  final BeautyService service;
  final Professional professional;
  final DateTime? selectedDate;
  final SlotLoadStatus slotStatus;
  final List<AvailabilitySlot> slots;
  final String? slotError;
  final DateTime? selectedStart;
  final bool homeService;
  final String address;
  final String notes;
  final bool submitting;
  final String? error;
  final Booking? createdBooking;
  final String? idempotencyKey;
  final BookingFlowStep step;
  final bool paymentHandled;

  /// Deposit due at booking time (base price x deposit %).
  double get depositAmount => service.basePrice * service.depositPercentage / 100;

  double get balanceAmount => service.basePrice - depositAmount;

  /// Whether home-service can be selected for this booking.
  bool get homeServiceAvailable =>
      service.homeServiceAvailable && professional.homeServiceEnabled;

  /// Ready to submit once a slot is picked (and, for home-service bookings,
  /// a delivery address is provided) and no request is in flight.
  bool get readyToSubmit =>
      selectedStart != null &&
      !submitting &&
      (!homeService || address.trim().isNotEmpty);

  /// Whether the user tried to confirm with an empty home-service address.
  bool get addressRequired => homeService && address.trim().isEmpty;

  BookingFlowState copyWith({
    DateTime? selectedDate,
    SlotLoadStatus? slotStatus,
    List<AvailabilitySlot>? slots,
    Object? slotError = _keep,
    Object? selectedStart = _keep,
    bool? homeService,
    String? address,
    String? notes,
    bool? submitting,
    Object? error = _keep,
    Object? createdBooking = _keep,
    String? idempotencyKey,
    BookingFlowStep? step,
    bool? paymentHandled,
  }) {
    return BookingFlowState(
      service: service,
      professional: professional,
      selectedDate: selectedDate ?? this.selectedDate,
      slotStatus: slotStatus ?? this.slotStatus,
      slots: slots ?? this.slots,
      slotError: identical(slotError, _keep) ? this.slotError : slotError as String?,
      selectedStart:
          identical(selectedStart, _keep) ? this.selectedStart : selectedStart as DateTime?,
      homeService: homeService ?? this.homeService,
      address: address ?? this.address,
      notes: notes ?? this.notes,
      submitting: submitting ?? this.submitting,
      error: identical(error, _keep) ? this.error : error as String?,
      createdBooking:
          identical(createdBooking, _keep) ? this.createdBooking : createdBooking as Booking?,
      idempotencyKey: idempotencyKey ?? this.idempotencyKey,
      step: step ?? this.step,
      paymentHandled: paymentHandled ?? this.paymentHandled,
    );
  }

  static const Object _keep = Object();
}

/// Drives the booking wizard: date -> slot -> details -> submit.
class BookingFlowController extends FamilyNotifier<BookingFlowState, BookingFlowArgs> {
  int _slotRequestId = 0;
  bool _idempotencyInitialised = false;
  bool _disposed = false;

  @override
  BookingFlowState build(BookingFlowArgs arg) {
    ref.onDispose(() => _disposed = true);
    if (!_idempotencyInitialised) {
      _idempotencyInitialised = true;
      state = BookingFlowState(
        service: arg.service,
        professional: arg.professional,
        idempotencyKey: _newIdempotencyKey(),
      );
    }
    return state;
  }

  void selectDate(DateTime date) {
    state = state.copyWith(
      selectedDate: date,
      selectedStart: null,
      slotStatus: SlotLoadStatus.loading,
      slotError: null,
    );
    _loadSlots(date);
  }

  void selectSlot(DateTime start) {
    state = state.copyWith(selectedStart: start, error: null);
  }

  void setHomeService(bool value) {
    state = state.copyWith(homeService: value, error: null);
  }

  void setAddress(String value) {
    state = state.copyWith(address: value, error: null);
  }

  void setNotes(String value) {
    state = state.copyWith(notes: value, error: null);
  }

  void setStep(BookingFlowStep value) {
    state = state.copyWith(step: value);
  }

  void markPaymentHandled() {
    state = state.copyWith(paymentHandled: true);
  }

  void retrySlots() {
    final date = state.selectedDate;
    if (date == null) return;
    state = state.copyWith(slotStatus: SlotLoadStatus.loading, slotError: null);
    _loadSlots(date);
  }

  Future<void> _loadSlots(DateTime date) async {
    if (_disposed) return;
    final id = ++_slotRequestId;
    try {
      final slots = await ref.read(bookingApiProvider).fetchSlots(
            state.professional.id,
            date: date,
            durationMinutes: state.service.durationMinutes,
          );
      if (_disposed || id != _slotRequestId) return;
      state = state.copyWith(slotStatus: SlotLoadStatus.ready, slots: slots);
    } on AppException catch (e) {
      if (_disposed || id != _slotRequestId) return;
      state = state.copyWith(slotStatus: SlotLoadStatus.error, slotError: e.message);
    } catch (_) {
      if (_disposed || id != _slotRequestId) return;
      state = state.copyWith(
        slotStatus: SlotLoadStatus.error,
        slotError: 'Could not load available times. Please try again.',
      );
    }
  }

  Future<void> submit() async {
    if (_disposed) return;
    final current = state;
    final start = current.selectedStart;
    if (start == null || current.submitting) return;

    state = current.copyWith(submitting: true, error: null);
    try {
      final booking = await ref.read(bookingApiProvider).createBooking(
            serviceId: current.service.id,
            startAt: start,
            homeService: current.homeService,
            locationAddress: current.homeService ? current.address : '',
            customerNotes: current.notes,
            idempotencyKey: current.idempotencyKey,
          );
      if (_disposed) return;
      state = state.copyWith(submitting: false, createdBooking: booking);
    } on AppException catch (e) {
      if (_disposed) return;
      state = state.copyWith(submitting: false, error: e.message);
    } catch (_) {
      if (_disposed) return;
      state = state.copyWith(
        submitting: false,
        error: 'Could not complete your booking. Please try again.',
      );
    }
  }

  String _newIdempotencyKey() => DateTime.now().microsecondsSinceEpoch.toString();
}

final bookingFlowProvider =
    NotifierProvider.family<BookingFlowController, BookingFlowState, BookingFlowArgs>(
  BookingFlowController.new,
);

// ---------------------------------------------------------------------------
// My bookings + detail
// ---------------------------------------------------------------------------

enum MyBookingsStatus { loading, ready, error }

class MyBookingsState {
  const MyBookingsState({required this.status, this.bookings = const [], this.error});

  final MyBookingsStatus status;
  final List<Booking> bookings;
  final String? error;
}

/// Loads the customer's bookings and exposes refresh.
class MyBookingsController extends Notifier<MyBookingsState> {
  bool _disposed = false;

  @override
  MyBookingsState build() {
    ref.onDispose(() => _disposed = true);
    _load();
    return const MyBookingsState(status: MyBookingsStatus.loading);
  }

  Future<void> _load() async {
    if (_disposed) return;
    try {
      final bookings = await ref.read(bookingApiProvider).fetchMyBookings();
      if (_disposed) return;
      state = MyBookingsState(status: MyBookingsStatus.ready, bookings: bookings);
    } on AppException catch (e) {
      if (_disposed) return;
      state = MyBookingsState(status: MyBookingsStatus.error, error: e.message);
    } catch (_) {
      if (_disposed) return;
      state = const MyBookingsState(
        status: MyBookingsStatus.error,
        error: 'Could not load your bookings. Please try again.',
      );
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (state.bookings.isEmpty) {
      state = const MyBookingsState(status: MyBookingsStatus.loading);
    }
    await _load();
  }
}

final myBookingsControllerProvider = NotifierProvider<MyBookingsController, MyBookingsState>(
  MyBookingsController.new,
);

/// Single booking detail (requires the booking to belong to the user).
final bookingDetailProvider = FutureProvider.family<Booking, String>((ref, id) {
  return ref.watch(bookingApiProvider).fetchBooking(id);
});

/// Status-change timeline for a booking.
final bookingHistoryProvider = FutureProvider.family<List<BookingStatusEvent>, String>((ref, id) {
  return ref.watch(bookingApiProvider).fetchHistory(id);
});

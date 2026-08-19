import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/availability.dart';
import '../../models/beauty_service.dart';
import '../../models/booking.dart';
import '../../models/deal.dart';
import '../../models/payout.dart';
import '../../models/portfolio_item.dart';
import '../../models/professional.dart';
import '../../models/review.dart';
import '../../models/verification.dart';
import 'data/pro_api.dart';

enum ProListStatus { loading, ready, error }

class ProListState<T> {
  const ProListState({required this.status, this.items = const [], this.error});

  final ProListStatus status;
  final List<T> items;
  final String? error;
}

/// Loads a pro-owned list from [load] and exposes refresh + mutation hooks.
class ProListController<T> extends Notifier<ProListState<T>> {
  @override
  ProListState<T> build() {
    _load();
    return ProListState<T>(status: ProListStatus.loading);
  }

  Future<void> _load() async {
    try {
      final items = await load();
      state = ProListState<T>(status: ProListStatus.ready, items: items);
    } on AppException catch (e) {
      state = ProListState<T>(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = ProListState<T>(
        status: ProListStatus.error,
        error: 'Could not load. Please try again.',
      );
    }
  }

  Future<List<T>> load() async => const [];

  Future<void> refresh() async {
    state = ProListState<T>(status: ProListStatus.loading);
    await _load();
  }
}

// ---------------------------------------------------------------------------
// Profile
// ---------------------------------------------------------------------------

class ProProfileState {
  const ProProfileState({this.status = ProListStatus.loading, this.profile, this.error});

  final ProListStatus status;
  final Professional? profile;
  final String? error;
}

class ProProfileController extends Notifier<ProProfileState> {
  @override
  ProProfileState build() {
    _load();
    return const ProProfileState();
  }

  Future<void> _load() async {
    try {
      final profile = await ref.read(proApiProvider).fetchMyProfile();
      state = ProProfileState(status: ProListStatus.ready, profile: profile);
    } on ApiException catch (e) {
      // No professional record yet: surface the "set up your studio" state
      // instead of an error so a freshly registered pro can onboard.
      if (e.code == 'professional_not_found') {
        state = const ProProfileState(status: ProListStatus.ready);
        return;
      }
      state = ProProfileState(status: ProListStatus.error, error: e.message);
    } on AppException catch (e) {
      state = ProProfileState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProProfileState(status: ProListStatus.error, error: 'Could not load your profile.');
    }
  }

  Future<void> refresh() async {
    state = const ProProfileState();
    await _load();
  }

  Future<void> create(Map<String, dynamic> payload) async {
    final profile = await ref.read(proApiProvider).createMyProfile(payload);
    state = ProProfileState(status: ProListStatus.ready, profile: profile);
  }

  Future<void> update(Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final profile = await api.updateMyProfile(payload);
    state = ProProfileState(status: ProListStatus.ready, profile: profile);
  }
}

final proProfileControllerProvider =
    NotifierProvider<ProProfileController, ProProfileState>(ProProfileController.new);

// ---------------------------------------------------------------------------
// Bookings
// ---------------------------------------------------------------------------

class ProBookingsController extends Notifier<ProListState<Booking>> {
  @override
  ProListState<Booking> build() {
    _load();
    return const ProListState<Booking>(status: ProListStatus.loading);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(proApiProvider).fetchProBookings();
      state = ProListState(status: ProListStatus.ready, items: items);
    } on AppException catch (e) {
      state = ProListState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProListState(status: ProListStatus.error, error: 'Could not load your bookings.');
    }
  }

  Future<void> refresh() async {
    state = const ProListState(status: ProListStatus.loading);
    await _load();
  }

  Future<void> runAction(Booking booking, String action) async {
    final api = ref.read(proApiProvider);
    final updated = switch (action) {
      'confirm' => await api.confirmBooking(booking.id),
      'start' => await api.startBooking(booking.id),
      'complete' => await api.completeBooking(booking.id),
      _ => booking,
    };
    state = ProListState(
      status: ProListStatus.ready,
      items: [for (final b in state.items) b.id == updated.id ? updated : b],
    );
  }
}

final proBookingsControllerProvider =
    NotifierProvider<ProBookingsController, ProListState<Booking>>(ProBookingsController.new);

// ---------------------------------------------------------------------------
// Services
// ---------------------------------------------------------------------------

class ProServicesController extends Notifier<ProListState<BeautyService>> {
  @override
  ProListState<BeautyService> build() {
    _load();
    return const ProListState<BeautyService>(status: ProListStatus.loading);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(proApiProvider).fetchMyServices();
      state = ProListState(status: ProListStatus.ready, items: items);
    } on AppException catch (e) {
      state = ProListState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProListState(status: ProListStatus.error, error: 'Could not load your services.');
    }
  }

  Future<void> refresh() async {
    state = const ProListState(status: ProListStatus.loading);
    await _load();
  }

  Future<void> create(Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final created = await api.createService(payload);
    state = ProListState(
      status: ProListStatus.ready,
      items: [created, ...state.items],
    );
  }

  Future<void> update(String id, Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final updated = await api.updateService(id, payload);
    state = ProListState(
      status: ProListStatus.ready,
      items: [for (final s in state.items) s.id == id ? updated : s],
    );
  }

  Future<void> remove(String id) async {
    final api = ref.read(proApiProvider);
    await api.deleteService(id);
    state = ProListState(
      status: ProListStatus.ready,
      items: [for (final s in state.items) if (s.id != id) s],
    );
  }
}

final proServicesControllerProvider =
    NotifierProvider<ProServicesController, ProListState<BeautyService>>(ProServicesController.new);

// ---------------------------------------------------------------------------
// Availability
// ---------------------------------------------------------------------------

class ProAvailabilityState {
  const ProAvailabilityState({
    this.status = ProListStatus.loading,
    this.windows = const [],
    this.exceptions = const [],
    this.error,
  });

  final ProListStatus status;
  final List<AvailabilityWindow> windows;
  final List<AvailabilityException> exceptions;
  final String? error;
}

class ProAvailabilityController extends Notifier<ProAvailabilityState> {
  @override
  ProAvailabilityState build() {
    _load();
    return const ProAvailabilityState();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(proApiProvider);
      final windows = await api.fetchWindows();
      final exceptions = await api.fetchExceptions();
      state = ProAvailabilityState(
        status: ProListStatus.ready,
        windows: windows,
        exceptions: exceptions,
      );
    } on AppException catch (e) {
      state = ProAvailabilityState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProAvailabilityState(status: ProListStatus.error, error: 'Could not load availability.');
    }
  }

  Future<void> refresh() async {
    state = const ProAvailabilityState();
    await _load();
  }

  Future<void> saveWindows(List<Map<String, dynamic>> windows) async {
    final api = ref.read(proApiProvider);
    final saved = await api.saveWindows(windows);
    state = ProAvailabilityState(
      status: ProListStatus.ready,
      windows: saved,
      exceptions: state.exceptions,
    );
  }

  void localAdd(int day, int start, int end, List<AvailabilityWindow> current) {
    state = ProAvailabilityState(
      status: ProListStatus.ready,
      windows: [
        ...current,
        AvailabilityWindow(
          id: '',
          professionalId: '',
          dayOfWeek: day,
          startMinutes: start,
          endMinutes: end,
        ),
      ],
      exceptions: state.exceptions,
    );
  }

  void localUpdate(String id, int start, int end, List<AvailabilityWindow> current) {
    state = ProAvailabilityState(
      status: ProListStatus.ready,
      windows: [
        for (final w in current)
          if (w.id == id)
            AvailabilityWindow(
              id: w.id,
              professionalId: w.professionalId,
              dayOfWeek: w.dayOfWeek,
              startMinutes: start,
              endMinutes: end,
            )
          else
            w,
      ],
      exceptions: state.exceptions,
    );
  }

  Future<void> addException(Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final created = await api.addException(payload);
    state = ProAvailabilityState(
      status: ProListStatus.ready,
      windows: state.windows,
      exceptions: [created, ...state.exceptions],
    );
  }

  Future<void> removeException(String id) async {
    final api = ref.read(proApiProvider);
    await api.deleteException(id);
    state = ProAvailabilityState(
      status: ProListStatus.ready,
      windows: state.windows,
      exceptions: [for (final e in state.exceptions) if (e.id != id) e],
    );
  }
}

final proAvailabilityControllerProvider =
    NotifierProvider<ProAvailabilityController, ProAvailabilityState>(ProAvailabilityController.new);

// ---------------------------------------------------------------------------
// Portfolio
// ---------------------------------------------------------------------------

class ProPortfolioController extends Notifier<ProListState<PortfolioItem>> {
  @override
  ProListState<PortfolioItem> build() {
    _load();
    return const ProListState<PortfolioItem>(status: ProListStatus.loading);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(proApiProvider).fetchMyPortfolio();
      state = ProListState(status: ProListStatus.ready, items: items);
    } on AppException catch (e) {
      state = ProListState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProListState(status: ProListStatus.error, error: 'Could not load your portfolio.');
    }
  }

  Future<void> refresh() async {
    state = const ProListState(status: ProListStatus.loading);
    await _load();
  }

  Future<void> create(Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final created = await api.createPortfolioItem(payload);
    state = ProListState(status: ProListStatus.ready, items: [created, ...state.items]);
  }

  Future<void> update(String id, Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final updated = await api.updatePortfolioItem(id, payload);
    state = ProListState(
      status: ProListStatus.ready,
      items: [for (final p in state.items) p.id == id ? updated : p],
    );
  }

  Future<void> remove(String id) async {
    final api = ref.read(proApiProvider);
    await api.deletePortfolioItem(id);
    state = ProListState(
      status: ProListStatus.ready,
      items: [for (final p in state.items) if (p.id != id) p],
    );
  }
}

final proPortfolioControllerProvider =
    NotifierProvider<ProPortfolioController, ProListState<PortfolioItem>>(ProPortfolioController.new);

// ---------------------------------------------------------------------------
// Deals
// ---------------------------------------------------------------------------

class ProDealsController extends Notifier<ProListState<Deal>> {
  @override
  ProListState<Deal> build() {
    _load();
    return const ProListState<Deal>(status: ProListStatus.loading);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(proApiProvider).fetchMyDeals();
      state = ProListState(status: ProListStatus.ready, items: items);
    } on AppException catch (e) {
      state = ProListState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProListState(status: ProListStatus.error, error: 'Could not load your deals.');
    }
  }

  Future<void> refresh() async {
    state = const ProListState(status: ProListStatus.loading);
    await _load();
  }

  Future<void> create(Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final created = await api.createDeal(payload);
    state = ProListState(status: ProListStatus.ready, items: [created, ...state.items]);
  }

  Future<void> toggle(String id, bool active) async {
    final api = ref.read(proApiProvider);
    await api.updateDeal(id, {'is_active': active});
    state = ProListState(
      status: ProListStatus.ready,
      items: [for (final d in state.items) d.id == id ? _withActive(d, active) : d],
    );
  }

  Deal _withActive(Deal d, bool active) => Deal(
        id: d.id,
        professionalId: d.professionalId,
        code: d.code,
        name: d.name,
        discountType: d.discountType,
        discountValue: d.discountValue,
        minOrderAmount: d.minOrderAmount,
        timesUsed: d.timesUsed,
        isActive: active,
      );
}

final proDealsControllerProvider =
    NotifierProvider<ProDealsController, ProListState<Deal>>(ProDealsController.new);

// ---------------------------------------------------------------------------
// Reviews
// ---------------------------------------------------------------------------

class ProReviewsController extends Notifier<ProListState<Review>> {
  @override
  ProListState<Review> build() {
    _load();
    return const ProListState<Review>(status: ProListStatus.loading);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(proApiProvider).fetchProReviews();
      state = ProListState(status: ProListStatus.ready, items: items);
    } on AppException catch (e) {
      state = ProListState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProListState(status: ProListStatus.error, error: 'Could not load reviews.');
    }
  }

  Future<void> refresh() async {
    state = const ProListState(status: ProListStatus.loading);
    await _load();
  }

  Future<void> respond(String id, String response) async {
    final api = ref.read(proApiProvider);
    final updated = await api.respondToReview(id, response);
    state = ProListState(
      status: ProListStatus.ready,
      items: [for (final r in state.items) r.id == id ? updated : r],
    );
  }
}

final proReviewsControllerProvider =
    NotifierProvider<ProReviewsController, ProListState<Review>>(ProReviewsController.new);

// ---------------------------------------------------------------------------
// Verification
// ---------------------------------------------------------------------------

class ProVerificationController extends Notifier<ProListState<VerificationDocument>> {
  @override
  ProListState<VerificationDocument> build() {
    _load();
    return const ProListState<VerificationDocument>(status: ProListStatus.loading);
  }

  Future<void> _load() async {
    try {
      final items = await ref.read(proApiProvider).fetchVerificationDocs();
      state = ProListState(status: ProListStatus.ready, items: items);
    } on AppException catch (e) {
      state = ProListState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProListState(status: ProListStatus.error, error: 'Could not load verification documents.');
    }
  }

  Future<void> refresh() async {
    state = const ProListState(status: ProListStatus.loading);
    await _load();
  }

  Future<void> submit(Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final created = await api.submitVerificationDoc(payload);
    state = ProListState(status: ProListStatus.ready, items: [created, ...state.items]);
  }
}

final proVerificationControllerProvider =
    NotifierProvider<ProVerificationController, ProListState<VerificationDocument>>(
  ProVerificationController.new,
);

// ---------------------------------------------------------------------------
// Payouts
// ---------------------------------------------------------------------------
class ProPayoutsState {
  const ProPayoutsState({
    this.status = ProListStatus.loading,
    this.balance = const PayoutBalance(),
    this.accounts = const [],
    this.requests = const [],
    this.error,
  });

  final ProListStatus status;
  final PayoutBalance balance;
  final List<PayoutAccount> accounts;
  final List<Payout> requests;
  final String? error;
}

class ProPayoutsController extends Notifier<ProPayoutsState> {
  @override
  ProPayoutsState build() {
    _load();
    return const ProPayoutsState();
  }

  Future<void> _load() async {
    try {
      final api = ref.read(proApiProvider);
      final balance = await api.fetchBalance();
      final accounts = await api.fetchAccounts();
      final requests = await api.fetchPayoutRequests();
      state = ProPayoutsState(
        status: ProListStatus.ready,
        balance: balance,
        accounts: accounts,
        requests: requests,
      );
    } on AppException catch (e) {
      state = ProPayoutsState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProPayoutsState(status: ProListStatus.error, error: 'Could not load payouts.');
    }
  }

  Future<void> refresh() async {
    state = const ProPayoutsState();
    await _load();
  }

  Future<void> addAccount(Map<String, dynamic> payload) async {
    final api = ref.read(proApiProvider);
    final created = await api.addAccount(payload);
    state = ProPayoutsState(
      status: ProListStatus.ready,
      balance: state.balance,
      accounts: [created, ...state.accounts],
      requests: state.requests,
    );
  }

  Future<void> setDefault(String id) async {
    final api = ref.read(proApiProvider);
    await api.setDefaultAccount(id);
    state = ProPayoutsState(
      status: ProListStatus.ready,
      balance: state.balance,
      accounts: [
        for (final a in state.accounts)
          PayoutAccount(
            id: a.id,
            professionalId: a.professionalId,
            bankName: a.bankName,
            bankCode: a.bankCode,
            accountNumber: a.accountNumber,
            accountName: a.accountName,
            isVerified: a.isVerified,
            isDefault: a.id == id,
          ),
      ],
      requests: state.requests,
    );
  }

  Future<void> removeAccount(String id) async {
    final api = ref.read(proApiProvider);
    await api.deleteAccount(id);
    state = ProPayoutsState(
      status: ProListStatus.ready,
      balance: state.balance,
      accounts: [for (final a in state.accounts) if (a.id != id) a],
      requests: state.requests,
    );
  }

  Future<Payout> request({required double amount, String? accountId, String note = ''}) async {
    final api = ref.read(proApiProvider);
    final created = await api.requestPayout(amount: amount, accountId: accountId, note: note);
    state = ProPayoutsState(
      status: ProListStatus.ready,
      balance: state.balance,
      accounts: state.accounts,
      requests: [created, ...state.requests],
    );
    return created;
  }
}

final proPayoutsControllerProvider =
    NotifierProvider<ProPayoutsController, ProPayoutsState>(ProPayoutsController.new);

// ---------------------------------------------------------------------------
// Earnings
// ---------------------------------------------------------------------------

class ProEarningsState {
  const ProEarningsState({
    this.status = ProListStatus.loading,
    this.earnings = const EarningsSummary(),
    this.error,
  });

  final ProListStatus status;
  final EarningsSummary earnings;
  final String? error;
}

/// Loads the pro-facing earnings snapshot shown on the studio dashboard.
class ProEarningsController extends Notifier<ProEarningsState> {
  @override
  ProEarningsState build() {
    _load();
    return const ProEarningsState();
  }

  Future<void> _load() async {
    try {
      final earnings = await ref.read(proApiProvider).fetchEarnings();
      state = ProEarningsState(status: ProListStatus.ready, earnings: earnings);
    } on ApiException catch (e) {
      // No professional record yet: show an empty snapshot instead of an error.
      if (e.code == 'professional_profile_required') {
        state = const ProEarningsState(status: ProListStatus.ready);
        return;
      }
      state = ProEarningsState(status: ProListStatus.error, error: e.message);
    } on AppException catch (e) {
      state = ProEarningsState(status: ProListStatus.error, error: e.message);
    } catch (_) {
      state = const ProEarningsState(status: ProListStatus.error, error: 'Could not load earnings.');
    }
  }

  Future<void> refresh() async {
    state = const ProEarningsState();
    await _load();
  }
}

final proEarningsControllerProvider =
    NotifierProvider<ProEarningsController, ProEarningsState>(ProEarningsController.new);

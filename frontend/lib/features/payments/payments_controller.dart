import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/errors/app_exception.dart';
import '../../models/booking.dart';
import '../../models/payment.dart';
import 'data/payment_api.dart';

/// What is being paid for on the checkout screen.
class PaymentFlowArgs {
  const PaymentFlowArgs({required this.bookingId, required this.amountType});

  final String bookingId;

  /// DEPOSIT | BALANCE | FULL
  final String amountType;

  /// Amount shown to the user is derived from the booking; the backend always
  /// recomputes the due amount server-side.
  double amountFor(Booking booking) {
    switch (amountType) {
      case 'BALANCE':
        return booking.balanceAmount;
      case 'FULL':
        return booking.totalAmount;
      default:
        return booking.depositAmount;
    }
  }

  String labelFor() {
    switch (amountType) {
      case 'BALANCE':
        return 'Pay balance';
      case 'FULL':
        return 'Pay full amount';
      default:
        return 'Pay deposit';
    }
  }
}

enum PaymentFlowStatus { idle, creating, awaiting, succeeded, failed }

class PaymentFlowState {
  const PaymentFlowState({
    this.status = PaymentFlowStatus.idle,
    this.intent,
    this.error,
  });

  final PaymentFlowStatus status;
  final PaymentIntent? intent;
  final String? error;
}

/// Drives checkout: create intent -> open gateway page -> poll until terminal.
class PaymentFlowController extends FamilyNotifier<PaymentFlowState, PaymentFlowArgs> {
  bool _polling = false;
  bool _disposed = false;

  @override
  PaymentFlowState build(PaymentFlowArgs arg) {
    ref.onDispose(() => _disposed = true);
    return const PaymentFlowState();
  }

  /// Creates (or reuses) the intent. In mock mode the backend marks it
  /// SUCCEEDED immediately; in live mode we land on [PaymentFlowStatus.awaiting].
  Future<void> start() async {
    final current = state;
    if (current.status == PaymentFlowStatus.creating) return;
    state = const PaymentFlowState(status: PaymentFlowStatus.creating);
    try {
      final intent = await ref
          .read(paymentApiProvider)
          .createIntent(bookingId: arg.bookingId, amountType: arg.amountType);
      _apply(intent);
    } on AppException catch (e) {
      state = PaymentFlowState(status: PaymentFlowStatus.failed, error: e.message);
    } catch (_) {
      state = const PaymentFlowState(
        status: PaymentFlowStatus.failed,
        error: 'Could not start the payment. Please try again.',
      );
    }
  }

  /// Single status refresh (manual "Check status" button).
  Future<void> checkStatus() async {
    final intent = state.intent;
    if (intent == null) return;
    try {
      final updated = await ref.read(paymentApiProvider).fetchIntent(intent.id);
      _apply(updated);
    } catch (_) {
      // Keep the last known state; a transient network error is fine here.
    }
  }

  /// Polls the intent until it reaches a terminal status.
  Future<void> startPolling({int intervalSeconds = 3, int maxTries = 20}) async {
    if (_polling || _disposed) return;
    _polling = true;
    try {
      for (var i = 0; i < maxTries; i++) {
        if (_disposed) return;
        await Future.delayed(Duration(seconds: intervalSeconds));
        if (_disposed) return;
        await checkStatus();
        if (state.status == PaymentFlowStatus.succeeded ||
            state.status == PaymentFlowStatus.failed) {
          return;
        }
      }
      // Guaranteed final check so a lapsed poll window never leaves the UI
      // stuck on a spinner forever.
      if (!_disposed) await checkStatus();
    } finally {
      _polling = false;
    }
  }

  void _apply(PaymentIntent intent) {
    if (intent.isSucceeded) {
      state = PaymentFlowState(status: PaymentFlowStatus.succeeded, intent: intent);
    } else if (intent.isFailed || intent.isCancelled) {
      state = PaymentFlowState(
        status: PaymentFlowStatus.failed,
        intent: intent,
        error: intent.isCancelled
            ? 'The payment was cancelled.'
            : 'The payment did not go through. Please try again.',
      );
    } else {
      state = PaymentFlowState(status: PaymentFlowStatus.awaiting, intent: intent);
    }
  }
}

final paymentFlowProvider = NotifierProvider.family<PaymentFlowController, PaymentFlowState, PaymentFlowArgs>(
  PaymentFlowController.new,
);

/// Existing DEPOSIT intent for a booking - used to show deposit status on the
/// booking detail screen without creating anything.
final bookingDepositIntentProvider = FutureProvider.family<PaymentIntent?, String>((ref, bookingId) {
  return ref.watch(paymentApiProvider).fetchDepositIntentForBooking(bookingId);
});

// ---------------------------------------------------------------------------
// Wallet
// ---------------------------------------------------------------------------

enum WalletStatus { loading, ready, error }

class WalletState {
  const WalletState({
    required this.status,
    this.wallet,
    this.items = const [],
    this.total = 0,
    this.error,
  });

  final WalletStatus status;
  final PaymentWallet? wallet;
  final List<LedgerEntry> items;
  final int total;
  final String? error;
}

/// Loads the wallet balance and transaction history.
class WalletController extends Notifier<WalletState> {
  bool _disposed = false;

  @override
  WalletState build() {
    ref.onDispose(() => _disposed = true);
    _load();
    return const WalletState(status: WalletStatus.loading);
  }

  Future<void> _load() async {
    if (_disposed) return;
    try {
      final api = ref.read(paymentApiProvider);
      final results = await Future.wait([
        api.fetchWallet(),
        api.fetchTransactions(),
      ]);
      if (_disposed) return;
      final wallet = results[0] as PaymentWallet? ??
          const PaymentWallet(userId: '', currency: 'NGN', balance: 0);
      final tx = results[1] as ({List<LedgerEntry> items, int total})?;
      if (tx == null) {
        state = const WalletState(
          status: WalletStatus.error,
          error: 'Could not load your wallet. Please try again.',
        );
        return;
      }
      state = WalletState(
        status: WalletStatus.ready,
        wallet: wallet,
        items: tx.items,
        total: tx.total,
      );
    } on AppException catch (e) {
      if (_disposed) return;
      state = WalletState(status: WalletStatus.error, error: e.message);
    } catch (_) {
      if (_disposed) return;
      state = const WalletState(
        status: WalletStatus.error,
        error: 'Could not load your wallet. Please try again.',
      );
    }
  }

  Future<void> refresh() async {
    if (_disposed) return;
    if (state.wallet == null) {
      state = const WalletState(status: WalletStatus.loading);
    }
    await _load();
  }
}

final walletControllerProvider = NotifierProvider<WalletController, WalletState>(WalletController.new);

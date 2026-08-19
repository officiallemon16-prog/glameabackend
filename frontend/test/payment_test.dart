import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/features/payments/data/payment_api.dart';
import 'package:glamea/features/payments/payments_controller.dart';
import 'package:glamea/models/booking.dart';
import 'package:glamea/models/payment.dart';

class FakePaymentApi extends PaymentApi {
  FakePaymentApi() : super(Dio());

  PaymentIntent pendingIntent = const PaymentIntent(
    id: 'int-1',
    bookingId: 'b-1',
    customerId: 'u-1',
    amountType: 'DEPOSIT',
    amount: 100,
    currency: 'NGN',
    status: 'PENDING',
    providerCharge: 0,
    platformFee: 0,
    gateway: 'paystack',
    gatewayReference: 'PS_ref-1',
    authorizationUrl: 'https://checkout.example/ps_ref-1',
  );

  PaymentIntent? depositIntent;
  String? lastBookingId;
  String? lastAmountType;

  @override
  Future<PaymentIntent> createIntent({
    required String bookingId,
    String amountType = 'DEPOSIT',
  }) async {
    lastBookingId = bookingId;
    lastAmountType = amountType;
    return pendingIntent;
  }

  @override
  Future<PaymentIntent> fetchIntent(String id) async => pendingIntent;

  @override
  Future<PaymentIntent?> fetchDepositIntentForBooking(String bookingId) async {
    return depositIntent;
  }
}

const booking = Booking(
  id: 'b-1',
  professionalId: 'pro-1',
  customerId: 'u-1',
  serviceId: 's-1',
  status: 'PENDING',
  startAt: null,
  endAt: null,
  baseAmount: 1000,
  totalAmount: 1000,
  depositAmount: 100,
  balanceAmount: 900,
  currency: 'NGN',
  homeService: false,
);

void main() {
  group('PaymentIntent', () {
    test('parses full payload with gateway checkout url', () {
      final intent = PaymentIntent.fromJson(const {
        'id': 'int-1',
        'booking_id': 'b-1',
        'customer_id': 'c-1',
        'amount_type': 'DEPOSIT',
        'amount': 100,
        'currency': 'NGN',
        'status': 'PENDING',
        'gateway': 'paystack',
        'gateway_reference': 'PS_ref-1',
        'authorization_url': 'https://checkout.example/ps_ref-1',
        'provider_charge': 1.5,
        'platform_fee': 8,
        'created_at': '2026-08-13T12:00:00Z',
      });

      expect(intent.id, 'int-1');
      expect(intent.amountType, 'DEPOSIT');
      expect(intent.status, 'PENDING');
      expect(intent.isPending, isTrue);
      expect(intent.isSucceeded, isFalse);
      expect(intent.isTerminal, isFalse);
      expect(intent.authorizationUrl, 'https://checkout.example/ps_ref-1');
      expect(intent.gatewayReference, 'PS_ref-1');
      expect(intent.statusLabel, 'Awaiting payment');
    });

    test('succeeded intent is terminal and labelled Paid', () {
      final intent = PaymentIntent.fromJson(const {
        'id': 'int-2',
        'booking_id': 'b-1',
        'customer_id': 'c-1',
        'amount_type': 'DEPOSIT',
        'amount': 100,
        'currency': 'NGN',
        'status': 'SUCCEEDED',
        'provider_charge': 0,
        'platform_fee': 0,
      });

      expect(intent.isSucceeded, isTrue);
      expect(intent.isTerminal, isTrue);
      expect(intent.statusLabel, 'Paid');
      expect(intent.authorizationUrl, isNull);
    });

    test('missing fields fall back safely', () {
      final intent = PaymentIntent.fromJson(const {'id': 'int-3'});

      expect(intent.status, 'PENDING');
      expect(intent.amount, 0);
      expect(intent.currency, 'NGN');
      expect(intent.gateway, isNull);
    });
  });

  group('PaymentWallet', () {
    test('parses balance payload', () {
      final wallet = PaymentWallet.fromJson(const {
        'user_id': 'u-1',
        'currency': 'NGN',
        'balance': 2500,
        'updated_at': '2026-08-13T12:00:00Z',
      });

      expect(wallet.balance, 2500);
      expect(wallet.currency, 'NGN');
      expect(wallet.updatedAt, isNotNull);
    });

    test('missing fields default to zero balance', () {
      final wallet = PaymentWallet.fromJson(const {});
      expect(wallet.balance, 0);
      expect(wallet.currency, 'NGN');
    });
  });

  group('LedgerEntry', () {
    test('parses credit earning entry', () {
      final entry = LedgerEntry.fromJson(const {
        'id': 'l-1',
        'user_id': 'u-1',
        'booking_id': 'b-1',
        'type': 'CREDIT',
        'category': 'EARNING',
        'amount': 920,
        'balance_after': 920,
        'currency': 'NGN',
        'reference': 'earn_b-1',
        'created_at': '2026-08-13T12:00:00Z',
      });

      expect(entry.isCredit, isTrue);
      expect(entry.categoryLabel, 'Earnings');
      expect(entry.bookingId, 'b-1');
    });

    test('debit entries are not credits', () {
      final entry = LedgerEntry.fromJson(const {
        'id': 'l-2',
        'user_id': 'u-1',
        'type': 'DEBIT',
        'category': 'DEPOSIT',
        'amount': 100,
        'balance_after': 0,
        'currency': 'NGN',
        'reference': 'ledger_x',
      });

      expect(entry.isCredit, isFalse);
      expect(entry.categoryLabel, 'Deposit');
    });
  });

  group('PaymentFlowArgs', () {
    test('amounts are derived from the booking per amount type', () {
      const deposit = PaymentFlowArgs(bookingId: 'b-1', amountType: 'DEPOSIT');
      const balance = PaymentFlowArgs(bookingId: 'b-1', amountType: 'BALANCE');
      const full = PaymentFlowArgs(bookingId: 'b-1', amountType: 'FULL');

      expect(deposit.amountFor(booking), 100);
      expect(balance.amountFor(booking), 900);
      expect(full.amountFor(booking), 1000);
      expect(deposit.labelFor(), 'Pay deposit');
      expect(balance.labelFor(), 'Pay balance');
    });
  });

  group('PaymentFlowController', () {
    test('pending intent with checkout url lands in awaiting state', () async {
      final container = ProviderContainer(
        overrides: [paymentApiProvider.overrideWithValue(FakePaymentApi())],
      );
      addTearDown(container.dispose);

      const args = PaymentFlowArgs(bookingId: 'b-1', amountType: 'DEPOSIT');
      final notifier = container.read(paymentFlowProvider(args).notifier);

      await notifier.start();

      final state = container.read(paymentFlowProvider(args));
      expect(state.status, PaymentFlowStatus.awaiting);
      expect(state.intent?.authorizationUrl, isNotNull);
    });

    test('mock succeeded intent lands directly in succeeded state', () async {
      final api = FakePaymentApi();
      api.pendingIntent = PaymentIntent.fromJson(const {
        'id': 'int-1',
        'booking_id': 'b-1',
        'customer_id': 'u-1',
        'amount_type': 'DEPOSIT',
        'amount': 100,
        'currency': 'NGN',
        'status': 'SUCCEEDED',
        'provider_charge': 0,
        'platform_fee': 0,
        'gateway': 'mock',
      });
      final container = ProviderContainer(overrides: [paymentApiProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);

      const args = PaymentFlowArgs(bookingId: 'b-1', amountType: 'DEPOSIT');
      await container.read(paymentFlowProvider(args).notifier).start();

      final state = container.read(paymentFlowProvider(args));
      expect(state.status, PaymentFlowStatus.succeeded);
      expect(api.lastBookingId, 'b-1');
      expect(api.lastAmountType, 'DEPOSIT');
    });

    test('checkStatus transitions awaiting to succeeded once paid', () async {
      final api = FakePaymentApi();
      final container = ProviderContainer(overrides: [paymentApiProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);

      const args = PaymentFlowArgs(bookingId: 'b-1', amountType: 'DEPOSIT');
      final notifier = container.read(paymentFlowProvider(args).notifier);

      await notifier.start();
      expect(container.read(paymentFlowProvider(args)).status, PaymentFlowStatus.awaiting);

      api.pendingIntent = PaymentIntent.fromJson(const {
        'id': 'int-1',
        'booking_id': 'b-1',
        'customer_id': 'u-1',
        'amount_type': 'DEPOSIT',
        'amount': 100,
        'currency': 'NGN',
        'status': 'SUCCEEDED',
        'provider_charge': 0,
        'platform_fee': 0,
      });

      await notifier.checkStatus();

      final state = container.read(paymentFlowProvider(args));
      expect(state.status, PaymentFlowStatus.succeeded);
      expect(state.intent?.isSucceeded, isTrue);
    });
  });

  group('bookingDepositIntentProvider', () {
    test('returns the deposit intent when it exists', () async {
      final api = FakePaymentApi();
      api.depositIntent = PaymentIntent.fromJson(const {
        'id': 'int-1',
        'booking_id': 'b-1',
        'customer_id': 'u-1',
        'amount_type': 'DEPOSIT',
        'amount': 100,
        'currency': 'NGN',
        'status': 'SUCCEEDED',
        'provider_charge': 0,
        'platform_fee': 0,
      });
      final container = ProviderContainer(overrides: [paymentApiProvider.overrideWithValue(api)]);
      addTearDown(container.dispose);

      final intent = await container.read(bookingDepositIntentProvider('b-1').future);

      expect(intent, isNotNull);
      expect(intent!.isSucceeded, isTrue);
    });

    test('returns null when no deposit intent exists yet', () async {
      final container = ProviderContainer(
        overrides: [paymentApiProvider.overrideWithValue(FakePaymentApi())],
      );
      addTearDown(container.dispose);

      final intent = await container.read(bookingDepositIntentProvider('b-1').future);

      expect(intent, isNull);
    });
  });
}

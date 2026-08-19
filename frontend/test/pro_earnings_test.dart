import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/core/errors/app_exception.dart';
import 'package:glamea/features/pro/data/pro_api.dart';
import 'package:glamea/features/pro/pro_controller.dart';
import 'package:glamea/features/pro/screens/pro_dashboard_tab.dart';
import 'package:glamea/models/booking.dart';
import 'package:glamea/models/payout.dart';
import 'package:glamea/models/professional.dart';

const summaryJson = {
  'currency': 'NGN',
  'total_earned': 125000.0,
  'available': 40000.0,
  'pending': 25000.0,
  'wallet_balance': 65000.0,
  'this_week': 8500.0,
  'this_month': 30000.0,
};

class FakeProApi extends ProApi {
  FakeProApi() : super(Dio());

  @override
  Future<EarningsSummary> fetchEarnings() async {
    return EarningsSummary.fromJson(summaryJson);
  }

  @override
  Future<Professional> fetchMyProfile() async {
    return const Professional(
      id: 'pro-1',
      userId: 'u-1',
      displayName: "Ada's Studio",
      city: 'Lagos',
      country: 'NG',
      rating: 4.5,
    );
  }

  @override
  Future<List<Booking>> fetchProBookings({int limit = 100, int offset = 0}) async =>
      const [];

  @override
  Future<PayoutBalance> fetchBalance() async =>
      const PayoutBalance(available: 40000, pending: 25000, total: 125000);

  @override
  Future<List<PayoutAccount>> fetchAccounts() async => const [];

  @override
  Future<List<Payout>> fetchPayoutRequests({int limit = 100, int offset = 0}) async =>
      const [];
}

class NoProfileProApi extends FakeProApi {
  @override
  Future<EarningsSummary> fetchEarnings() async {
    throw const ApiException(
      'create a professional profile first',
      code: 'professional_profile_required',
      statusCode: 403,
    );
  }

  @override
  Future<Professional> fetchMyProfile() async {
    throw const ApiException(
      'no professional profile exists',
      code: 'professional_not_found',
      statusCode: 404,
    );
  }
}

class FailingEarningsProApi extends FakeProApi {
  @override
  Future<EarningsSummary> fetchEarnings() async {
    throw const ApiException(
      'Earnings are temporarily unavailable.',
      code: 'server_error',
      statusCode: 500,
    );
  }
}

void main() {
  group('EarningsSummary', () {
    test('parses the full payload', () {
      final e = EarningsSummary.fromJson(summaryJson);

      expect(e.currency, 'NGN');
      expect(e.totalEarned, 125000.0);
      expect(e.available, 40000.0);
      expect(e.pending, 25000.0);
      expect(e.walletBalance, 65000.0);
      expect(e.thisWeek, 8500.0);
      expect(e.thisMonth, 30000.0);
    });

    test('missing fields fall back safely', () {
      final e = EarningsSummary.fromJson(const {});

      expect(e.currency, 'NGN');
      expect(e.totalEarned, 0);
      expect(e.available, 0);
      expect(e.pending, 0);
      expect(e.walletBalance, 0);
      expect(e.thisWeek, 0);
      expect(e.thisMonth, 0);
    });
  });

  group('ProEarningsController', () {
    test('loads earnings into ready state', () async {
      final container = ProviderContainer(
        overrides: [proApiProvider.overrideWithValue(FakeProApi())],
      );
      addTearDown(container.dispose);

      container.read(proEarningsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(proEarningsControllerProvider);
      expect(state.status, ProListStatus.ready);
      expect(state.earnings.totalEarned, 125000.0);
      expect(state.earnings.thisMonth, 30000.0);
    });

    test('refresh reloads the snapshot', () async {
      final container = ProviderContainer(
        overrides: [proApiProvider.overrideWithValue(FakeProApi())],
      );
      addTearDown(container.dispose);
      container.read(proEarningsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await container.read(proEarningsControllerProvider.notifier).refresh();

      final state = container.read(proEarningsControllerProvider);
      expect(state.status, ProListStatus.ready);
      expect(state.earnings.available, 40000.0);
    });

    test('missing professional profile yields an empty snapshot', () async {
      final container = ProviderContainer(
        overrides: [proApiProvider.overrideWithValue(NoProfileProApi())],
      );
      addTearDown(container.dispose);

      container.read(proEarningsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(proEarningsControllerProvider);
      expect(state.status, ProListStatus.ready);
      expect(state.earnings.totalEarned, 0);
    });

    test('fetch failure surfaces the error', () async {
      final container = ProviderContainer(
        overrides: [proApiProvider.overrideWithValue(FailingEarningsProApi())],
      );
      addTearDown(container.dispose);

      container.read(proEarningsControllerProvider);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(proEarningsControllerProvider);
      expect(state.status, ProListStatus.error);
      expect(state.error, 'Earnings are temporarily unavailable.');
    });
  });

  group('Pro dashboard earnings card', () {
    testWidgets('renders the earnings snapshot', (tester) async {
      tester.view.physicalSize = const Size(800, 1800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(
        ProviderScope(
          overrides: [proApiProvider.overrideWithValue(FakeProApi())],
          child: const MaterialApp(
            home: Scaffold(body: ProDashboardTab()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('Available balance'), findsOneWidget);
      expect(find.text('₦40,000'), findsOneWidget);
      expect(find.text('Pending'), findsOneWidget);
      expect(find.text('₦25,000'), findsOneWidget);
      expect(find.text('Total earned'), findsOneWidget);
      expect(find.text('₦125,000'), findsOneWidget);
      expect(find.text('This week'), findsOneWidget);
      expect(find.text('₦8,500'), findsOneWidget);
      expect(find.text('This month'), findsOneWidget);
      expect(find.text('₦30,000'), findsOneWidget);
    });

    testWidgets('hides the earnings card until a profile exists', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [proApiProvider.overrideWithValue(NoProfileProApi())],
          child: const MaterialApp(
            home: Scaffold(body: ProDashboardTab()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      expect(find.text('No profile yet'), findsOneWidget);
      expect(find.text('Available balance'), findsNothing);
      expect(find.text('Total earned'), findsNothing);
    });

    testWidgets('tapping withdraw opens the payouts screen', (tester) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [proApiProvider.overrideWithValue(FakeProApi())],
          child: const MaterialApp(
            home: Scaffold(body: ProDashboardTab()),
          ),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Withdraw'));
      await tester.pumpAndSettle();

      expect(find.text('Payouts'), findsWidgets);
      expect(find.text('Available balance'), findsOneWidget);
      expect(find.text('₦40,000'), findsOneWidget);
    });
  });
}

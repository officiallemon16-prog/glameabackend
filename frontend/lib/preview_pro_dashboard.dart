import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/theme/app_colors.dart';
import 'app/theme/app_spacing.dart';
import 'app/theme/app_theme.dart';
import 'app/theme/app_typography.dart';
import 'features/pro/data/pro_api.dart';
import 'features/pro/screens/pro_availability_tab.dart';
import 'features/pro/screens/pro_bookings_tab.dart';
import 'features/pro/screens/pro_dashboard_tab.dart';
import 'features/pro/screens/pro_services_tab.dart';
import 'models/availability.dart';
import 'models/beauty_service.dart';
import 'models/booking.dart';
import 'models/payout.dart';
import 'models/professional.dart';
import 'shared/widgets/app_bar.dart';
import 'shared/widgets/app_card.dart';

/// Standalone preview of the redesigned pro dashboard.
/// Run with: flutter run -t lib/preview_pro_dashboard.dart -d chrome
void main() {
  runApp(
    ProviderScope(
      overrides: [proApiProvider.overrideWithValue(_PreviewProApi(Dio()))],
      child: MaterialApp(
        title: 'Glamea Pro preview',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: const PreviewShell(),
      ),
    ),
  );
}

class PreviewShell extends StatefulWidget {
  const PreviewShell({super.key});

  @override
  State<PreviewShell> createState() => _PreviewShellState();
}

class _PreviewShellState extends State<PreviewShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [
          ProDashboardTab(),
          ProBookingsTab(),
          ProServicesTab(),
          ProAvailabilityTab(),
          _PreviewAccountTab(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        backgroundColor: AppColors.white,
        indicatorColor: AppColors.roseGold.withValues(alpha: 0.24),
        surfaceTintColor: Colors.transparent,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard), label: 'Dashboard'),
          NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month), label: 'Bookings'),
          NavigationDestination(icon: Icon(Icons.content_cut_outlined), selectedIcon: Icon(Icons.content_cut), label: 'Services'),
          NavigationDestination(icon: Icon(Icons.schedule_outlined), selectedIcon: Icon(Icons.schedule), label: 'Availability'),
          NavigationDestination(icon: Icon(Icons.person_outline_rounded), selectedIcon: Icon(Icons.person_rounded), label: 'Account'),
        ],
      ),
    );
  }
}

/// Account tab is stubbed in the preview (avoids auth/go_router deps).
class _PreviewAccountTab extends StatelessWidget {
  const _PreviewAccountTab();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Column(
        children: [
          const GlameaPageHeader(title: 'Account'),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.all(AppSpacing.md),
              children: const [
                AppCard(
                  child: Row(
                    children: [
                      Icon(Icons.info_outline_rounded, color: AppColors.roseGold),
                      SizedBox(width: AppSpacing.sm),
                      Expanded(
                        child: Text(
                          'Account & logout are wired to the real app (auth, go_router).',
                          style: AppTextStyles.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewProApi extends ProApi {
  _PreviewProApi(super.dio);

  static final _now = DateTime.now();

  static const _profile = Professional(
    id: 'pro-1',
    userId: 'u-1',
    displayName: "Ada's Studio",
    businessName: "Ada's Studio",
    bio: 'Bridal & special-occasion makeup artist in Lagos.',
    rating: 4.8,
    reviewCount: 42,
    bookingCount: 156,
    completionRate: 0.97,
    status: 'ACTIVE',
    verificationStatus: 'VERIFIED',
    city: 'Lagos',
    country: 'Nigeria',
    homeServiceEnabled: true,
    serviceRadiusKm: 12,
    travelFeePerKm: 1500,
  );

  static final _bookings = [
    Booking(
      id: 'bk-1',
      professionalId: 'pro-1',
      customerId: 'c-1',
      serviceId: 'sv-1',
      status: 'CONFIRMED',
      startAt: _now.add(const Duration(days: 1, hours: 10)),
      endAt: _now.add(const Duration(days: 1, hours: 11, minutes: 30)),
      baseAmount: 85000,
      totalAmount: 85000,
      depositAmount: 21250,
      balanceAmount: 63750,
      currency: 'NGN',
      homeService: true,
      locationAddress: 'Victoria Island, Lagos',
      customerName: 'Chioma O.',
      serviceName: 'Bridal Makeup',
      createdAt: _now.subtract(const Duration(days: 3)),
    ),
    Booking(
      id: 'bk-2',
      professionalId: 'pro-1',
      customerId: 'c-2',
      serviceId: 'sv-2',
      status: 'PENDING',
      startAt: _now.add(const Duration(days: 2, hours: 14)),
      endAt: _now.add(const Duration(days: 2, hours: 14, minutes: 45)),
      baseAmount: 25000,
      totalAmount: 25000,
      depositAmount: 6250,
      balanceAmount: 18750,
      currency: 'NGN',
      homeService: false,
      customerName: 'Tunde A.',
      serviceName: 'Gel Manicure',
      createdAt: _now.subtract(const Duration(days: 1)),
    ),
    Booking(
      id: 'bk-3',
      professionalId: 'pro-1',
      customerId: 'c-3',
      serviceId: 'sv-3',
      status: 'COMPLETED',
      startAt: _now.subtract(const Duration(days: 3)),
      endAt: _now.subtract(const Duration(hours: 70)),
      baseAmount: 60000,
      totalAmount: 60000,
      depositAmount: 15000,
      balanceAmount: 45000,
      currency: 'NGN',
      homeService: true,
      customerName: 'Ngozi E.',
      serviceName: 'Makeup Class',
      createdAt: _now.subtract(const Duration(days: 10)),
    ),
    Booking(
      id: 'bk-4',
      professionalId: 'pro-1',
      customerId: 'c-4',
      serviceId: 'sv-1',
      status: 'COMPLETED',
      startAt: _now.subtract(const Duration(days: 8)),
      endAt: _now.subtract(const Duration(days: 8, hours: -2)),
      baseAmount: 85000,
      totalAmount: 85000,
      depositAmount: 21250,
      balanceAmount: 63750,
      currency: 'NGN',
      homeService: false,
      customerName: 'Fola B.',
      serviceName: 'Bridal Makeup',
      createdAt: _now.subtract(const Duration(days: 15)),
    ),
  ];

  static final _services = [
    const BeautyService(
      id: 'sv-1',
      professionalId: 'pro-1',
      name: 'Bridal Makeup',
      description: 'Full bridal glam, lashes included, trial available.',
      basePrice: 85000,
      currency: 'NGN',
      durationMinutes: 90,
      depositPercentage: 25,
      homeServiceAvailable: true,
      displayOrder: 1,
    ),
    const BeautyService(
      id: 'sv-2',
      professionalId: 'pro-1',
      name: 'Gel Manicure',
      description: 'Gel polish with nail shaping and cuticle care.',
      basePrice: 25000,
      currency: 'NGN',
      durationMinutes: 45,
      depositPercentage: 25,
      homeServiceAvailable: true,
      displayOrder: 2,
    ),
    const BeautyService(
      id: 'sv-3',
      professionalId: 'pro-1',
      name: 'Makeup Class',
      description: 'One-on-one or small group sessions.',
      basePrice: 60000,
      currency: 'NGN',
      durationMinutes: 120,
      depositPercentage: 50,
      homeServiceAvailable: false,
      displayOrder: 3,
    ),
  ];

  static final _windows = [
    const AvailabilityWindow(id: 'w-1', professionalId: 'pro-1', dayOfWeek: 1, startMinutes: 540, endMinutes: 1020),
    const AvailabilityWindow(id: 'w-2', professionalId: 'pro-1', dayOfWeek: 2, startMinutes: 540, endMinutes: 1020),
    const AvailabilityWindow(id: 'w-3', professionalId: 'pro-1', dayOfWeek: 3, startMinutes: 540, endMinutes: 1020),
    const AvailabilityWindow(id: 'w-4', professionalId: 'pro-1', dayOfWeek: 4, startMinutes: 540, endMinutes: 1020),
    const AvailabilityWindow(id: 'w-5', professionalId: 'pro-1', dayOfWeek: 5, startMinutes: 540, endMinutes: 1020),
    const AvailabilityWindow(id: 'w-6', professionalId: 'pro-1', dayOfWeek: 6, startMinutes: 600, endMinutes: 960),
  ];

  static const _account = PayoutAccount(
    id: 'acc-1',
    professionalId: 'pro-1',
    bankName: 'Zenith Bank',
    bankCode: '057',
    accountNumber: '0123456789',
    accountName: "Ada's Studio",
    isVerified: true,
    isDefault: true,
  );

  static final _payoutRequests = [
    Payout(
      id: 'po-1',
      professionalId: 'pro-1',
      payoutAccountId: 'acc-1',
      amount: 20000,
      currency: 'NGN',
      status: 'PENDING',
      note: 'Weekly withdrawal',
      createdAt: _now.subtract(const Duration(days: 2)),
      accountName: "Ada's Studio",
      bankName: 'Zenith Bank',
    ),
  ];

  @override
  Future<Professional> fetchMyProfile() async => _profile;

  @override
  Future<List<Booking>> fetchProBookings({int limit = 100, int offset = 0}) async =>
      _bookings;

  @override
  Future<List<BeautyService>> fetchMyServices() async => _services;

  @override
  Future<List<AvailabilityWindow>> fetchWindows() async => _windows;

  @override
  Future<List<AvailabilityException>> fetchExceptions({String? from}) async => const [];

  @override
  Future<List<PayoutAccount>> fetchAccounts() async => [_account];

  @override
  Future<List<Payout>> fetchPayoutRequests({int limit = 100, int offset = 0}) async =>
      _payoutRequests;

  @override
  Future<PayoutBalance> fetchBalance() async =>
      const PayoutBalance(available: 40000, pending: 25000, total: 125000);

  @override
  Future<EarningsSummary> fetchEarnings() async => const EarningsSummary(
        currency: 'NGN',
        totalEarned: 125000,
        available: 40000,
        pending: 25000,
        walletBalance: 65000,
        thisWeek: 8500,
        thisMonth: 30000,
      );
}

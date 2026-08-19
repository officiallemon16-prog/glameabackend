import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/deeplinks/deep_link_controller.dart';
import '../../features/auth/auth_controller.dart';
import '../../features/auth/screens/login_screen.dart';
import '../../features/auth/screens/otp_screen.dart';
import '../../features/auth/screens/register_screen.dart';
import '../../features/auth/screens/verify_email_screen.dart';
import '../../features/booking/booking_controller.dart';
import '../../features/booking/screens/booking_detail_screen.dart';
import '../../features/booking/screens/booking_flow_screen.dart';
import '../../features/booking/screens/my_bookings_screen.dart';
import '../../features/discovery/screens/category_screen.dart';
import '../../features/discovery/screens/look_screen.dart';
import '../../features/discovery/screens/professional_screen.dart';
import '../../features/discovery/screens/top_rated_screen.dart';
import '../../features/disputes/screens/dispute_detail_screen.dart';
import '../../features/disputes/screens/disputes_list_screen.dart';
import '../../features/disputes/screens/raise_dispute_screen.dart';
import '../../features/favorites/favorites_screen.dart';
import '../../features/home/home_shell.dart';
import '../../features/location/location_map_screen.dart';
import '../../features/messaging/screens/chat_screen.dart';
import '../../features/onboarding/onboarding_screen.dart';
import '../../features/payments/payments_controller.dart';
import '../../features/payments/screens/in_app_payment_screen.dart';
import '../../features/payments/screens/payment_screen.dart';
import '../../features/payments/screens/wallet_screen.dart';
import '../../features/pro/pro_shell.dart';
import '../../features/pro/screens/pro_onboarding_screen.dart';
import '../../features/profile/screens/edit_profile_screen.dart';
import '../../features/profile/screens/notifications_screen.dart';
import '../../features/reviews/screens/my_reviews_screen.dart';
import '../../features/splash/splash_screen.dart';

/// Route paths (spec sections 7-16).
abstract final class AppRoutes {
  static const String splash = '/splash';
  static const String onboarding = '/onboarding';
  static const String login = '/login';
  static const String register = '/register';
  static const String otp = '/otp';
  static const String verifyEmail = '/verify-email';
  static const String home = '/home';
  static const String discover = '/discover';
  static const String pro = '/pro';
  static const String professional = '/professionals/:id';
  static const String category = '/categories/:slug';
  static const String booking = '/bookings/:id';
  static const String newBooking = '/bookings/new';
  static const String payBooking = '/bookings/:id/pay';
  static const String wallet = '/wallet';
  static const String look = '/looks/:id';
  static const String messages = '/messages';
  static const String chat = '/bookings/:id/chat';
  static const String editProfile = '/profile/edit';
  static const String notifications = '/notifications';
  static const String bookingList = '/bookings';
  static const String myReviews = '/reviews/me';
  static const String disputes = '/disputes';
  static const String disputeDetail = '/disputes/:id';
  static const String raiseDispute = '/bookings/:id/dispute';
  static const String location = '/location';
  static const String inAppPayment = '/payments/in-app';
  static const String proOnboarding = '/pro/onboarding';
  static const String favorites = '/favorites';
  static const String topRated = '/top-rated';

  static String professionalFor(String id) => '/professionals/$id';
  static String categoryFor(String slug) => '/categories/$slug';
  static String lookFor(String id) => '/looks/$id';
  static String bookingFor(String id) => '/bookings/$id';
  static String chatFor(String id) => '/bookings/$id/chat';
  static String payFor(String id) => '/bookings/$id/pay';
  static String disputeDetailFor(String id) => '/disputes/$id';
  static String raiseDisputeFor(String id) => '/bookings/$id/dispute';
}

/// Notifies go_router whenever the auth session changes so redirects re-run.
class RouterRefresh extends ChangeNotifier {
  void notify() => notifyListeners();
}

final routerRefreshProvider = Provider<RouterRefresh>((ref) {
  final notifier = RouterRefresh();
  ref.onDispose(notifier.dispose);
  return notifier;
});

/// Central app router. Redirect logic keeps the user where they should be
/// based on auth status; feature routes are added per phase.
final appRouterProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: AppRoutes.splash,
    refreshListenable: ref.watch(routerRefreshProvider),
    redirect: (context, state) {
      final auth = ref.read(authControllerProvider);
      if (auth.status == AuthStatus.initializing) return null;

      final location = state.matchedLocation;
      final authRoutes = {
        AppRoutes.splash,
        AppRoutes.onboarding,
        AppRoutes.login,
        AppRoutes.register,
        AppRoutes.otp,
      };

      if (auth.status == AuthStatus.verifyingPhone) {
        return location == AppRoutes.otp ? null : AppRoutes.otp;
      }
      if (auth.isAuthenticated) {
        // A pending deep link wins over the default landing destination.
        final deepLink = ref.read(pendingDeepLinkProvider);
        if (deepLink != null) {
          ref.read(pendingDeepLinkProvider.notifier).consume();
          return deepLink;
        }
        final isPro = auth.user?.role == 'PROFESSIONAL';
        if (authRoutes.contains(location)) {
          return isPro ? AppRoutes.pro : AppRoutes.home;
        }
        // Non-pro users hitting /pro get redirected to onboarding wizard.
        if (!isPro && location == AppRoutes.pro) {
          return AppRoutes.proOnboarding;
        }
        return null;
      }
      return authRoutes.contains(location) ? null : AppRoutes.onboarding;
    },
    routes: [
      GoRoute(
        path: AppRoutes.splash,
        builder: (context, state) => const SplashScreen(),
      ),
      GoRoute(
        path: AppRoutes.onboarding,
        builder: (context, state) => const OnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.login,
        builder: (context, state) => const LoginScreen(),
      ),
      GoRoute(
        path: AppRoutes.register,
        builder: (context, state) => const RegisterScreen(),
      ),
      GoRoute(
        path: AppRoutes.otp,
        builder: (context, state) => const OtpScreen(),
      ),
      GoRoute(
        path: AppRoutes.verifyEmail,
        builder: (context, state) => const VerifyEmailScreen(),
      ),
      GoRoute(
        path: AppRoutes.home,
        builder: (context, state) => const HomeShell(),
      ),
      GoRoute(
        // Landing target for discovery nudges/digests: opens the shell with
        // the Discover tab selected.
        path: AppRoutes.discover,
        builder: (context, state) => const HomeShell(initialIndex: 1),
      ),
      GoRoute(
        path: AppRoutes.pro,
        builder: (context, state) => const ProShell(),
      ),
      GoRoute(
        path: AppRoutes.proOnboarding,
        builder: (context, state) => const ProOnboardingScreen(),
      ),
      GoRoute(
        path: AppRoutes.professional,
        builder: (context, state) =>
            ProfessionalScreen(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.category,
        builder: (context, state) =>
            CategoryScreen(slug: state.pathParameters['slug'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.look,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is LookScreenData) return LookScreen(data: extra);
          return LookScreen(id: state.pathParameters['id'] ?? '');
        },
      ),
      GoRoute(
        path: AppRoutes.newBooking,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is BookingFlowArgs) return BookingFlowScreen(args: extra);
          return const Scaffold(
            body: Center(child: Text('No service selected for booking.')),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.booking,
        builder: (context, state) =>
            BookingDetailScreen(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.payBooking,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;
          if (extra is PaymentFlowArgs) return PaymentScreen(args: extra);
          return PaymentScreen(
            args: PaymentFlowArgs(bookingId: id, amountType: 'DEPOSIT'),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.inAppPayment,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is PaymentFlowArgs) return InAppPaymentScreen(args: extra);
          return const Scaffold(
            body: Center(child: Text('No payment details.')),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.wallet,
        builder: (context, state) => const WalletScreen(),
      ),
      GoRoute(
        path: AppRoutes.chat,
        builder: (context, state) =>
            ChatScreen(bookingId: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.bookingList,
        builder: (context, state) => const MyBookingsScreen(),
      ),
      GoRoute(
        path: AppRoutes.editProfile,
        builder: (context, state) => const EditProfileScreen(),
      ),
      GoRoute(
        path: AppRoutes.notifications,
        builder: (context, state) => const NotificationsScreen(),
      ),
      GoRoute(
        path: AppRoutes.myReviews,
        builder: (context, state) => const MyReviewsScreen(),
      ),
      GoRoute(
        path: AppRoutes.favorites,
        builder: (context, state) => const FavoritesScreen(),
      ),
      GoRoute(
        path: AppRoutes.topRated,
        builder: (context, state) => const TopRatedScreen(),
      ),
      GoRoute(
        path: AppRoutes.location,
        builder: (context, state) {
          final extra = state.extra;
          if (extra is LocationMapArgs) return LocationMapScreen(args: extra);
          return const Scaffold(
            body: Center(child: Text('No location selected.')),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.disputes,
        builder: (context, state) => const DisputesListScreen(),
      ),
      GoRoute(
        path: AppRoutes.disputeDetail,
        builder: (context, state) =>
            DisputeDetailScreen(id: state.pathParameters['id'] ?? ''),
      ),
      GoRoute(
        path: AppRoutes.raiseDispute,
        builder: (context, state) {
          final id = state.pathParameters['id'] ?? '';
          final extra = state.extra;
          if (extra is RaiseDisputeArgs) return RaiseDisputeScreen(args: extra);
          return RaiseDisputeScreen(
            args: RaiseDisputeArgs(bookingId: id, professionalName: ''),
          );
        },
      ),
    ],
  );
});

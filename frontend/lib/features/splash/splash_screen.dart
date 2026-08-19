import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_motion.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../auth/auth_controller.dart';

/// Route: /splash (spec section 7).
/// Full-screen beauty imagery, slow crossfade, Glamea logo and tagline:
/// "Discover your look. Find your artist. Book your beauty."
/// Once the crossfade completes it routes based on the session state.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key, this.onFinished});

  /// Optional hook called once the minimum splash time elapses.
  final VoidCallback? onFinished;

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  bool _done = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotion.slow,
    )..forward();
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        setState(() => _done = true);
        widget.onFinished?.call();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _navigate(AuthState auth) {
    if (_navigated || !mounted) return;
    _navigated = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = switch (auth.status) {
        AuthStatus.authenticated => AppRoutes.home,
        AuthStatus.verifyingPhone => AppRoutes.otp,
        _ => AppRoutes.onboarding,
      };
      context.go(route);
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authControllerProvider);
    if (_done && auth.status != AuthStatus.initializing) {
      _navigate(auth);
    }

    return Scaffold(
      backgroundColor: AppColors.primary,
      body: Stack(
        fit: StackFit.expand,
        children: [
          const _BeautyBackdrop(),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 88,
                  height: 88,
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(24),
                  ),
                  child: const Icon(Icons.auto_awesome, size: 44, color: AppColors.primary),
                ),
                const SizedBox(height: AppSpacing.lg),
                const Text(
                  'GLAMEA',
                  style: TextStyle(
                    color: AppColors.white,
                    fontFamily: 'PlusJakartaSans',
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 4,
                  ),
                ),
                const SizedBox(height: AppSpacing.xs),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
                  child: Text(
                    'Discover your look. Find your artist. Book your beauty.',
                    textAlign: TextAlign.center,
                    style: AppTextStyles.body.copyWith(color: AppColors.white.withValues(alpha: 0.9)),
                  ),
                ),
              ],
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xl),
              child: Text(
                'Made with love in Nigeria',
                style: AppTextStyles.caption.copyWith(color: AppColors.white.withValues(alpha: 0.6)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _BeautyBackdrop extends StatelessWidget {
  const _BeautyBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.primary, AppColors.roseGold],
          stops: [0.0, 1.0],
        ),
      ),
    );
  }
}

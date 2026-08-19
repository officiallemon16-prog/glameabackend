import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../shared/widgets/widgets.dart';

class OnboardingScreen extends ConsumerWidget {
  const OnboardingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 88,
                height: 88,
                decoration: BoxDecoration(
                  color: AppColors.primary,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: const Icon(Icons.auto_awesome,
                    color: AppColors.white, size: 44),
              ),
              const SizedBox(height: AppSpacing.xl),
              const Text(
                'Glamea',
                style: AppTextStyles.display,
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Discover your look.\nFind your artist.\nBook your beauty.',
                textAlign: TextAlign.center,
                style: AppTextStyles.body.copyWith(
                  color: AppColors.textSecondary,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 3),
              AppButton(
                label: 'Create account',
                onPressed: () => context.go(AppRoutes.register),
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: 'Log in',
                variant: AppButtonVariant.outline,
                onPressed: () => context.go(AppRoutes.login),
              ),
              const SizedBox(height: AppSpacing.xl),
            ],
          ),
        ),
      ),
    );
  }
}

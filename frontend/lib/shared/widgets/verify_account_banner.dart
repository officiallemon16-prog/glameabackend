import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router/app_router.dart';
import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';
import '../../features/profile/verify_nudge_controller.dart';

/// Small, dismissible banner nudging unverified users to verify their account.
class VerifyAccountBanner extends ConsumerWidget {
  const VerifyAccountBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Container(
      color: AppColors.warning.withValues(alpha: 0.15),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Row(
        children: [
          const Icon(Icons.verified_outlined, color: AppColors.warning, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: GestureDetector(
              onTap: () {
                ref.read(verifyNudgeControllerProvider.notifier).markShown();
                context.push(AppRoutes.verifyEmail);
              },
              child: Text(
                'Verify your account to unlock all features.',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: AppColors.textPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: AppColors.textMuted),
            onPressed: () =>
                ref.read(verifyNudgeControllerProvider.notifier).dismiss(),
          ),
        ],
      ),
    );
  }
}

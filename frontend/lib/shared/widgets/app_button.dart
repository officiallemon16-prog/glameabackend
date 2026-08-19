import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Glamea button variants.
enum AppButtonVariant { primary, secondary, outline, text }

class AppButton extends StatelessWidget {
  const AppButton({
    super.key,
    required this.label,
    this.onPressed,
    this.variant = AppButtonVariant.primary,
    this.icon,
    this.loading = false,
    this.expanded = true,
    this.height = AppDimens.minTouchTarget,
  });

  final String label;
  final VoidCallback? onPressed;
  final AppButtonVariant variant;
  final IconData? icon;
  final bool loading;
  final bool expanded;
  final double height;

  @override
  Widget build(BuildContext context) {
    final disabled = onPressed == null || loading;
    final filled = variant == AppButtonVariant.primary ||
        variant == AppButtonVariant.secondary;
    final foreground = filled ? AppColors.white : AppColors.primary;

    final Widget child;
    if (loading) {
      child = SizedBox(
        width: 22,
        height: 22,
        child: CircularProgressIndicator(strokeWidth: 2.2, color: foreground),
      );
    } else {
      child = Row(
        mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 20, color: foreground),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.button.copyWith(color: foreground),
            ),
          ),
        ],
      );
    }

    final Widget button = switch (variant) {
      AppButtonVariant.primary => FilledButton(
          onPressed: disabled ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.35),
          ),
          child: child,
        ),
      AppButtonVariant.secondary => FilledButton(
          onPressed: disabled ? null : onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: AppColors.roseGold,
            foregroundColor: AppColors.white,
            disabledBackgroundColor: AppColors.roseGold.withValues(alpha: 0.35),
          ),
          child: child,
        ),
      AppButtonVariant.outline => OutlinedButton(
          onPressed: disabled ? null : onPressed,
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.primary,
            side: const BorderSide(color: AppColors.primary),
            disabledForegroundColor: AppColors.textMuted,
          ),
          child: child,
        ),
      AppButtonVariant.text => TextButton(
          onPressed: disabled ? null : onPressed,
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            disabledForegroundColor: AppColors.textMuted,
          ),
          child: child,
        ),
    };

    return SizedBox(
      height: height,
      width: expanded ? double.infinity : null,
      child: button,
    );
  }
}

/// Full-bleed tap target with ripple, used for list items.
class AppInkWell extends StatelessWidget {
  const AppInkWell(
      {super.key, required this.onTap, required this.child, this.radius});

  final VoidCallback? onTap;
  final Widget child;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(radius ?? AppDimens.cardRadiusMobile),
        child: child,
      ),
    );
  }
}

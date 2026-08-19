import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../../core/connectivity/connectivity_service.dart';

/// Thin banner shown at the top of the app while the device is offline.
/// Hidden while connectivity is unknown (loading/error).
class OfflineBanner extends ConsumerWidget {
  const OfflineBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider);
    // Loading/error states mean the status is unknown: keep the banner hidden.
    // (Accessing .value on an AsyncError rethrows, hence the guards.)
    if (online.isLoading || online.hasError || online.value == true) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      color: AppColors.warning,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm, horizontal: AppSpacing.md),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.wifi_off, size: 16, color: AppColors.white),
          SizedBox(width: AppSpacing.xs),
          Flexible(
            child: Text(
              'You\'re offline. Some features may be unavailable.',
              textAlign: TextAlign.center,
              style: TextStyle(color: AppColors.white, fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

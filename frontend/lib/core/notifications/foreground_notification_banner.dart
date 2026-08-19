import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_spacing.dart';
import '../deeplinks/deep_link_controller.dart';
import 'notification_links.dart';
import 'notification_service.dart';

/// Lightweight in-app banner shown while the app is open and a push arrives.
/// Tapping routes the user exactly like tapping the system notification;
/// otherwise it auto-dismisses after a few seconds.
class ForegroundNotificationBanner extends ConsumerStatefulWidget {
  const ForegroundNotificationBanner({super.key});

  @override
  ConsumerState<ForegroundNotificationBanner> createState() =>
      _ForegroundNotificationBannerState();
}

class _ForegroundNotificationBannerState
    extends ConsumerState<ForegroundNotificationBanner> {
  Map<String, String>? _current;
  StreamSubscription<Map<String, String>>? _sub;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    final service = ref.read(notificationServiceProvider);
    _sub = service.foregroundMessages.listen((data) {
      if (!mounted) return;
      _dismissTimer?.cancel();
      setState(() => _current = data);
      _dismissTimer = Timer(const Duration(seconds: 6), () {
        if (mounted) setState(() => _current = null);
      });
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _sub?.cancel();
    super.dispose();
  }

  void _open() {
    final data = _current;
    _dismissTimer?.cancel();
    setState(() => _current = null);
    if (data == null) return;
    final link = deepLinkFromPushData(data);
    if (link == null) return;
    ref.read(pendingDeepLinkProvider.notifier).handleRaw(link);
  }

  void _dismiss() {
    _dismissTimer?.cancel();
    setState(() => _current = null);
  }

  @override
  Widget build(BuildContext context) {
    final data = _current;
    if (data == null) return const SizedBox.shrink();

    final title = (data['title'] ?? 'Glamea').isNotEmpty ? data['title']! : 'Glamea';
    final body = data['body'] ?? '';

    return Material(
      color: AppColors.white,
      elevation: 4,
      child: InkWell(
        onTap: _open,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
            child: Row(
              children: [
                const Icon(Icons.notifications_active,
                    size: 20, color: AppColors.primary),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (body.isNotEmpty)
                        Text(
                          body,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.textSecondary,
                            fontSize: 13,
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _dismiss,
                  icon: const Icon(Icons.close, size: 18),
                  color: AppColors.textMuted,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

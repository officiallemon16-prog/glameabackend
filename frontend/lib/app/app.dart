import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/deeplinks/deep_link_controller.dart';
import '../core/notifications/foreground_notification_banner.dart';
import '../core/notifications/notification_links.dart';
import '../core/notifications/notification_service.dart';
import '../features/messaging/calls/call_screens.dart';
import '../shared/widgets/widgets.dart';
import 'router/app_router.dart';
import 'theme/app_theme.dart';

/// Glamea root widget.
class GlameaApp extends ConsumerStatefulWidget {
  const GlameaApp({super.key});

  @override
  ConsumerState<GlameaApp> createState() => _GlameaAppState();
}

class _GlameaAppState extends ConsumerState<GlameaApp> {
  @override
  void initState() {
    super.initState();
    _initPush();
  }

  Future<void> _initPush() async {
    final service = ref.read(notificationServiceProvider);
    await service.initialize(_onPushTap);
  }

  /// Routes a tapped notification to its screen by reusing the deep link
  /// machinery (queued until the user is authenticated).
  void _onPushTap(Map<String, String> data) {
    final link = deepLinkFromPushData(data);
    if (link == null) return;
    ref.read(pendingDeepLinkProvider.notifier).handleRaw(link);
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);

    return MaterialApp.router(
      title: 'Glamea',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      routerConfig: router,
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: const [Locale('en')],
      locale: const Locale('en'),
      // Renders the offline banner above the navigator without overlapping
      // screen content (the app pushes down instead).
      builder: (context, child) {
        // Responsive text scaling: keep typography comfortable across device
        // sizes (small phones get slightly smaller text, large ones a bit
        // larger) without touching the const theme tokens.
        final width = MediaQuery.of(context).size.width;
        final scale = (width / 375).clamp(0.85, 1.12);
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(scale),
          ),
          child: Column(
            children: [
              const OfflineBanner(),
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    child ?? const SizedBox.shrink(),
                    // Foreground push banner pinned to the top of the content.
                    const Align(
                      alignment: Alignment.topCenter,
                      child: ForegroundNotificationBanner(),
                    ),
                    const CallOverlay(),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

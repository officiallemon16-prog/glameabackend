import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/auth_controller.dart';
import '../../features/booking/screens/my_bookings_tab.dart';
import '../../features/discovery/feed_controller.dart';
import '../../features/discovery/screens/discover_tab.dart';
import '../../features/discovery/screens/home_tab.dart';
import '../../features/messaging/messaging_controller.dart';
import '../../features/messaging/screens/messages_tab.dart';
import '../../features/profile/screens/profile_tab.dart';
import '../../features/profile/verify_nudge_controller.dart';
import '../../shared/widgets/app_back_handler.dart';
import '../../shared/widgets/verify_account_banner.dart';
import '../../shared/widgets/widgets.dart';

/// Post-auth shell with the 5 primary destinations:
/// Home, Discover, Bookings, Messages, Profile (spec section 8).
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.initialIndex = 0});

  /// Tab to open on first build (e.g. 1 = Discover for nudges/digests).
  final int initialIndex;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _index = widget.initialIndex.clamp(0, 4).toInt();

  @override
  Widget build(BuildContext context) {
    final unread = ref.watch(unreadControllerProvider);
    ref.watch(verifyNudgeControllerProvider);
    final showVerify = ref
        .read(verifyNudgeControllerProvider.notifier)
        .shouldShow(ref.watch(authControllerProvider).user);

    return AppBackHandler(
      child: Scaffold(
        body: Column(
          children: [
            if (showVerify) const VerifyAccountBanner(),
            Expanded(
              child: IndexedStack(
                index: _index,
                children: [
                  HomeTab(onSeeAll: () => setState(() => _index = 1)),
                  const DiscoverTab(),
                  const MyBookingsTab(),
                  const MessagesTab(),
                  const ProfileTab(),
                ],
              ),
            ),
          ],
        ),
        bottomNavigationBar: GlameaNavBar(
          currentIndex: _index,
          onDestinationSelected: (i) {
            if (i == _index && i == 0) {
              ref.read(feedControllerProvider.notifier).refresh();
              // Scroll the feed back to the latest post when re-tapping Home.
              ref.read(homeScrollToTopProvider.notifier).state++;
            }
            setState(() => _index = i);
          },
          messagesUnread: unread,
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

/// Wraps a screen that lives *inside* the router navigator and intercepts the
/// Android/system back button so it navigates in-app instead of closing the
/// whole app.
///
/// At the very root (nothing left to pop) a second press within 2 seconds
/// exits the app; a single press only shows a hint.
class AppBackHandler extends StatefulWidget {
  const AppBackHandler({super.key, required this.child});

  final Widget child;

  @override
  State<AppBackHandler> createState() => _AppBackHandlerState();
}

class _AppBackHandlerState extends State<AppBackHandler> {
  DateTime? _lastBackPress;

  void _handleBack(bool didPop) {
    if (didPop) return;
    final router = GoRouter.of(context);
    if (router.canPop()) {
      router.pop();
      return;
    }
    final now = DateTime.now();
    if (_lastBackPress != null &&
        now.difference(_lastBackPress!) <= const Duration(seconds: 2)) {
      SystemNavigator.pop();
      return;
    }
    _lastBackPress = now;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Press back again to exit'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) => _handleBack(didPop),
      child: widget.child,
    );
  }
}

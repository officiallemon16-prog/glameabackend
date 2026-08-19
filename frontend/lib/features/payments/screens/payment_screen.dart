import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../payments_controller.dart';

/// Legacy checkout screen. Redirects to InAppPaymentScreen which handles
/// the platform-appropriate payment flow (new tab on web, WebView on mobile).
class PaymentScreen extends StatelessWidget {
  const PaymentScreen({super.key, required this.args});

  final PaymentFlowArgs args;

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (context.mounted) {
        context.pushReplacement(AppRoutes.inAppPayment, extra: args);
      }
    });
    return const Scaffold(
      body: Center(
        child: CircularProgressIndicator(),
      ),
    );
  }
}

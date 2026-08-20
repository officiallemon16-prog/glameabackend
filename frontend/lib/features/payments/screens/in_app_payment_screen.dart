import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../models/payment.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../payments_controller.dart';

class InAppPaymentScreen extends ConsumerStatefulWidget {
  const InAppPaymentScreen({super.key, required this.args});

  final PaymentFlowArgs args;

  @override
  ConsumerState<InAppPaymentScreen> createState() => _InAppPaymentScreenState();
}

class _InAppPaymentScreenState extends ConsumerState<InAppPaymentScreen> {
  @override
  void initState() {
    super.initState();
    ref.read(paymentFlowProvider(widget.args).notifier).start();
  }

  @override
  Widget build(BuildContext context) {
    final flow = ref.watch(paymentFlowProvider(widget.args));
    final intent = flow.intent;

    if (flow.status == PaymentFlowStatus.succeeded) {
      return _SuccessView(intent: intent);
    }

    if (flow.status == PaymentFlowStatus.failed) {
      return _ErrorView(flow: flow, ref: ref, args: widget.args);
    }

    final hasAuthUrl =
        intent?.authorizationUrl != null && intent!.authorizationUrl!.isNotEmpty;

    if (!hasAuthUrl) {
      return const _ProcessingView(label: 'Setting up payment...');
    }

    return _CheckoutView(args: widget.args, intent: intent!);
  }
}

// ---------------------------------------------------------------------------
// Success
// ---------------------------------------------------------------------------

class _SuccessView extends StatelessWidget {
  const _SuccessView({required this.intent});
  final dynamic intent;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlameaAppBar(title: 'Payment', showBack: false),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TweenAnimationBuilder<double>(
                tween: Tween(begin: 0.4, end: 1),
                duration: const Duration(milliseconds: 500),
                curve: Curves.elasticOut,
                child: Container(
                  width: 72,
                  height: 72,
                  decoration: const BoxDecoration(
                    color: AppColors.success,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.check_rounded, color: Colors.white, size: 40),
                ),
                builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                'Payment successful!',
                style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
              ),
              if (intent != null) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  '${intent!.currency} ${intent!.amount.toStringAsFixed(2)}',
                  style: AppTextStyles.headline2.copyWith(color: AppColors.primary),
                ),
              ],
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'View booking',
                icon: Icons.event_rounded,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: AppSpacing.sm),
              AppButton(
                label: 'Done',
                variant: AppButtonVariant.outline,
                onPressed: () => Navigator.of(context).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Error
// ---------------------------------------------------------------------------

class _ErrorView extends StatelessWidget {
  const _ErrorView({
    required this.flow,
    required this.ref,
    required this.args,
  });
  final PaymentFlowState flow;
  final WidgetRef ref;
  final PaymentFlowArgs args;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlameaAppBar(title: 'Payment'),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline_rounded, size: 56, color: AppColors.error),
              const SizedBox(height: AppSpacing.md),
              Text(
                flow.error ?? 'Payment failed. Please try again.',
                textAlign: TextAlign.center,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
              ),
              const SizedBox(height: AppSpacing.lg),
              AppButton(
                label: 'Try again',
                icon: Icons.refresh_rounded,
                onPressed: () {
                  ref.read(paymentFlowProvider(args).notifier).start();
                },
              ),
              const SizedBox(height: AppSpacing.sm),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Go back'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Processing
// ---------------------------------------------------------------------------

class _ProcessingView extends StatelessWidget {
  const _ProcessingView({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlameaAppBar(title: 'Payment'),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: AppSpacing.md),
            Text(label),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Checkout — embeds the gateway page in an in-app WebView and polls for status.
// ---------------------------------------------------------------------------

class _CheckoutView extends ConsumerStatefulWidget {
  const _CheckoutView({required this.args, required this.intent});
  final PaymentFlowArgs args;
  final PaymentIntent intent;

  @override
  ConsumerState<_CheckoutView> createState() => _CheckoutViewState();
}

class _CheckoutViewState extends ConsumerState<_CheckoutView> {
  late final WebViewController _controller;
  bool _verifying = false;

  @override
  void initState() {
    super.initState();
    final url = widget.intent.authorizationUrl ?? '';
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onNavigationRequest: (request) {
            if (_looksLikeSuccess(request.url)) _markVerifying();
            return NavigationDecision.navigate;
          },
          onPageFinished: (url) {
            if (_looksLikeSuccess(url)) _markVerifying();
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    // Keep polling so the UI flips to success/error as soon as the backend
    // marks the intent terminal - even if the gateway's redirect isn't caught.
    ref.read(paymentFlowProvider(widget.args).notifier).startPolling(
          intervalSeconds: 3,
          maxTries: 40,
        );
  }

  bool _looksLikeSuccess(String url) {
    final lower = url.toLowerCase();
    return lower.contains('glamea://') ||
        lower.contains('status=success') ||
        lower.contains('status=complete') ||
        lower.contains('&paid=') ||
        lower.contains('tx_ref=') ||
        lower.contains('trxref=') ||
        lower.contains('/callback') ||
        lower.contains('/return');
  }

  void _markVerifying() {
    if (!mounted) return;
    setState(() => _verifying = true);
    ref.read(paymentFlowProvider(widget.args).notifier).checkStatus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlameaAppBar(
        title: 'Complete payment',
        actions: [
          if (widget.intent.gatewayReference != null)
            Padding(
              padding: const EdgeInsets.only(right: AppSpacing.md),
              child: Center(
                child: Text(
                  'Ref: ${widget.intent.gatewayReference}',
                  style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                ),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.close),
            tooltip: 'Close',
            onPressed: () {
              ref.read(paymentFlowProvider(widget.args).notifier).checkStatus();
              Navigator.of(context).pop(false);
            },
          ),
        ],
      ),
      body: Stack(
        children: [
          WebViewWidget(controller: _controller),
          if (_verifying)
            Container(
              color: Colors.black45,
              child: Center(
                child: Container(
                  padding: const EdgeInsets.all(AppSpacing.lg),
                  decoration: BoxDecoration(
                    color: AppColors.white,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: AppColors.primary),
                      SizedBox(height: AppSpacing.md),
                      Text('Verifying your payment…'),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

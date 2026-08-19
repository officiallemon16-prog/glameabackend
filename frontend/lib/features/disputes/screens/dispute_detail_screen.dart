import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../models/dispute.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../disputes_controller.dart';

/// Dispute detail with the message thread (replies allowed while open).
class DisputeDetailScreen extends ConsumerStatefulWidget {
  const DisputeDetailScreen({super.key, required this.id});

  final String id;

  @override
  ConsumerState<DisputeDetailScreen> createState() => _DisputeDetailScreenState();
}

class _DisputeDetailScreenState extends ConsumerState<DisputeDetailScreen> {
  final _input = TextEditingController();

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = disputeDetailControllerProvider(widget.id);
    final state = ref.watch(provider);
    final userId = ref.watch(authControllerProvider).user?.id ?? '';
    final dispute = state.dispute;

    ref.listen(provider.select((s) => s.sendError), (previous, next) {
      if (next != null && next != previous) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next)));
      }
    });

    return Scaffold(
      appBar: const GlameaAppBar(title: 'Dispute'),
      body: Column(
        children: [
          Expanded(
            child: switch (state.status) {
              DisputeDetailStatus.loading => const Padding(
                  padding: EdgeInsets.all(AppSpacing.md),
                  child: SkeletonList(count: 4),
                ),
              DisputeDetailStatus.error => ErrorState(
                  message: state.error ?? 'Could not load this dispute.',
                  onRetry: () => ref.read(provider.notifier).refresh(),
                ),
              DisputeDetailStatus.ready => _Thread(
                  state: state,
                  userId: userId,
                ),
            },
          ),
          if (state.status == DisputeDetailStatus.ready && dispute != null && dispute.isOpen)
            _Composer(
              controller: _input,
              sending: state.sending,
              onSend: _send,
            ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final sent = await ref.read(disputeDetailControllerProvider(widget.id).notifier).addMessage(text);
    if (sent) _input.clear();
  }
}

class _Thread extends StatelessWidget {
  const _Thread({required this.state, required this.userId});

  final DisputeDetailState state;
  final String userId;

  @override
  Widget build(BuildContext context) {
    final dispute = state.dispute;
    if (dispute == null) {
      return const ErrorState(message: 'Dispute not found.', onRetry: null);
    }

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.md),
      children: [
        _StatusBanner(dispute: dispute),
        if (dispute.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.md),
          _DescriptionCard(dispute: dispute),
        ],
        const SizedBox(height: AppSpacing.md),
        Text('Conversation', style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
        const SizedBox(height: AppSpacing.sm),
        if (state.messages.isEmpty)
          const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: Text('No messages yet.'),
          )
        else
          for (final message in state.messages) _MessageBubble(message: message, isMine: message.senderId == userId),
      ],
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.dispute});

  final Dispute dispute;

  @override
  Widget build(BuildContext context) {
    final color = dispute.isOpen ? AppColors.warning : AppColors.success;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                dispute.isOpen ? Icons.gavel_outlined : Icons.verified_outlined,
                color: color,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.xs),
              Text(
                dispute.statusLabel,
                style: AppTextStyles.title.copyWith(color: color),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            dispute.reason,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
          if (dispute.resolution.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(
              dispute.resolution,
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textPrimary),
            ),
          ],
        ],
      ),
    );
  }
}

class _DescriptionCard extends StatelessWidget {
  const _DescriptionCard({required this.dispute});

  final Dispute dispute;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Text(
        dispute.description,
        style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMine});

  final DisputeMessage message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.78),
        margin: const EdgeInsets.only(bottom: AppSpacing.xs),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(
          color: isMine ? AppColors.primary : AppColors.white,
          borderRadius: BorderRadius.only(
            topLeft: Radius.circular(isMine ? AppSpacing.md : AppSpacing.xs),
            topRight: Radius.circular(isMine ? AppSpacing.xs : AppSpacing.md),
            bottomLeft: const Radius.circular(AppSpacing.md),
            bottomRight: const Radius.circular(AppSpacing.md),
          ),
          border: isMine ? null : Border.all(color: AppColors.borderSubtle),
        ),
        child: Column(
          crossAxisAlignment: isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            Text(
              message.body,
              style: AppTextStyles.bodyMedium.copyWith(
                color: isMine ? AppColors.white : AppColors.textPrimary,
              ),
            ),
            if (message.createdAt != null)
              Text(
                Formatters.time(message.createdAt!),
                style: AppTextStyles.caption.copyWith(
                  color: isMine
                      ? AppColors.white.withValues(alpha: 0.7)
                      : AppColors.textMuted,
                  fontSize: 11,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: controller,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(hintText: 'Write a message…', isDense: true),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            SizedBox(
              height: 44,
              child: IconButton.filled(
                onPressed: sending ? null : onSend,
                style: IconButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  disabledBackgroundColor: AppColors.primary.withValues(alpha: 0.5),
                  foregroundColor: AppColors.white,
                  disabledForegroundColor: AppColors.white,
                ),
                icon: sending
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.white),
                      )
                    : const Icon(Icons.send_rounded, size: 20),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

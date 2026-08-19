import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/dispute.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_states.dart';
import '../disputes_controller.dart';

/// Disputes the current user is part of.
class DisputesListScreen extends ConsumerWidget {
  const DisputesListScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(myDisputesControllerProvider);

    return Scaffold(
      appBar: const GlameaAppBar(title: 'Disputes'),
      body: switch (state.status) {
        MyDisputesStatus.loading => const Padding(
            padding: EdgeInsets.all(AppSpacing.md),
            child: SkeletonList(count: 4),
          ),
        MyDisputesStatus.error => ErrorState(
            message: state.error ?? 'Could not load disputes.',
            onRetry: () => ref.read(myDisputesControllerProvider.notifier).refresh(),
          ),
        MyDisputesStatus.ready => RefreshIndicator(
            onRefresh: () => ref.read(myDisputesControllerProvider.notifier).refresh(),
            color: AppColors.primary,
            child: state.items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: const [
                      SizedBox(height: 120),
                      EmptyState(
                        icon: Icons.gavel_outlined,
                        title: 'No disputes',
                        message: 'If something goes wrong with a booking, you can raise a dispute here.',
                      ),
                    ],
                  )
                : ListView.separated(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    itemCount: state.items.length,
                    separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
                    itemBuilder: (context, index) {
                      final dispute = state.items[index];
                      return _DisputeCard(
                        dispute: dispute,
                        onTap: () => context.push(AppRoutes.disputeDetailFor(dispute.id)),
                      );
                    },
                  ),
          ),
      },
    );
  }
}

class _DisputeCard extends StatelessWidget {
  const _DisputeCard({required this.dispute, required this.onTap});

  final Dispute dispute;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = dispute.isOpen ? AppColors.warning : AppColors.success;
    return Material(
      color: AppColors.white,
      borderRadius: BorderRadius.circular(AppSpacing.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSpacing.md),
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  dispute.isOpen ? Icons.gavel_outlined : Icons.verified_outlined,
                  color: color,
                  size: 20,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      dispute.reason,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: AppColors.textPrimary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (dispute.createdAt != null)
                      Text(
                        Formatters.date(dispute.createdAt!),
                        style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                      ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  dispute.statusLabel,
                  style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

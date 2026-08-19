import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/payment.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../payments_controller.dart';

/// Wallet balance + transaction history.
class WalletScreen extends ConsumerWidget {
  const WalletScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(walletControllerProvider);

    return Scaffold(
      appBar: const GlameaAppBar(title: 'Wallet'),
      body: switch (state.status) {
        WalletStatus.loading => const SkeletonWallet(),
        WalletStatus.error => ErrorState(
            message: state.error ?? 'Could not load your wallet.',
            onRetry: () => ref.read(walletControllerProvider.notifier).refresh(),
          ),
        WalletStatus.ready => RefreshIndicator(
            onRefresh: () => ref.read(walletControllerProvider.notifier).refresh(),
            color: AppColors.primary,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(AppSpacing.md),
              children: [
                _BalanceCard(wallet: state.wallet),
                const SizedBox(height: AppSpacing.lg),
                Text(
                  'Transactions',
                  style: AppTextStyles.title.copyWith(color: AppColors.textPrimary),
                ),
                const SizedBox(height: AppSpacing.sm),
                if (state.items.isEmpty)
                  const EmptyState(
                    icon: Icons.receipt_long_outlined,
                    title: 'No transactions yet',
                    message: 'Payments and earnings will show up here.',
                  )
                else
                  AppCard(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                    child: Column(
                      children: [
                        for (var i = 0; i < state.items.length; i++) ...[
                          _TransactionRow(entry: state.items[i]),
                          if (i != state.items.length - 1)
                            const Divider(
                              height: 1,
                              indent: 16,
                              endIndent: 16,
                              color: AppColors.borderSubtle,
                            ),
                        ],
                      ],
                    ),
                  ),
                const SizedBox(height: AppSpacing.xl),
              ],
            ),
          ),
      },
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.wallet});

  final PaymentWallet? wallet;

  @override
  Widget build(BuildContext context) {
    final balance = wallet?.balance ?? 0;
    final currency = wallet?.currency ?? 'NGN';
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.primary, AppColors.roseGold],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(AppSpacing.md),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.account_balance_wallet_outlined,
              size: 28, color: Colors.white),
          const SizedBox(height: AppSpacing.sm),
          Text(
            'Available balance',
            style: AppTextStyles.bodyMedium.copyWith(color: Colors.white70),
          ),
          const SizedBox(height: AppSpacing.xxs),
          Text(
            Formatters.money(balance, currency),
            style: AppTextStyles.headline2.copyWith(color: Colors.white),
          ),
        ],
      ),
    );
  }
}

class _TransactionRow extends StatelessWidget {
  const _TransactionRow({required this.entry});

  final LedgerEntry entry;

  IconData get _icon {
    switch (entry.category) {
      case 'DEPOSIT':
      case 'BALANCE_PAYMENT':
      case 'FULL_PAYMENT':
        return Icons.account_balance_wallet_outlined;
      case 'EARNING':
        return Icons.trending_up_rounded;
      case 'PAYOUT':
        return Icons.send_outlined;
      case 'REFUND':
        return Icons.replay_rounded;
      default:
        return Icons.receipt_long_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = entry.isCredit ? AppColors.success : AppColors.textPrimary;
    final sign = entry.isCredit ? '+' : '-';
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
      child: Row(
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: AppColors.roseGold.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Icon(_icon, size: 18, color: AppColors.primary),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  entry.categoryLabel,
                  style: AppTextStyles.bodyMedium.copyWith(
                    color: AppColors.textPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (entry.createdAt != null)
                  Text(
                    Formatters.date(entry.createdAt),
                    style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
                  ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$sign${Formatters.money(entry.amount, entry.currency)}',
                style: AppTextStyles.bodyMedium.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
              ),
              Text(
                Formatters.money(entry.balanceAfter, entry.currency),
                style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

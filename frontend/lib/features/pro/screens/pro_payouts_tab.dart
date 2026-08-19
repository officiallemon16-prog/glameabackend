import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/payout.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../pro_controller.dart';

/// Professional payouts: balance, bank accounts, withdrawal requests.
class ProPayoutsTab extends ConsumerWidget {
  const ProPayoutsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(proPayoutsControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Text('Payouts', style: AppTextStyles.headline2),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(proPayoutsControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: _buildList(context, ref, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, ProPayoutsState state) {
    if (state.status == ProListStatus.loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [SkeletonList(count: 5)],
      );
    }
    if (state.status == ProListStatus.error) {
      return ListView(
        children: [
          ErrorState(
            message: state.error ?? 'Could not load payouts.',
            onRetry: () => ref.read(proPayoutsControllerProvider.notifier).refresh(),
          ),
        ],
      );
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      children: [
        _BalanceCard(balance: state.balance, onWithdraw: () => showGlameaSheet(context, child: const WithdrawSheet())),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            const Expanded(child: Text('Bank accounts', style: AppTextStyles.title)),
            IconButton(
              onPressed: () => showGlameaSheet(context, child: const AccountSheet()),
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              tooltip: 'Add account',
            ),
          ],
        ),
        if (state.accounts.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text('No payout accounts yet. Add a bank account to receive withdrawals.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          )
        else
          for (final account in state.accounts)
            _AccountCard(
              account: account,
              onDefault: () => ref.read(proPayoutsControllerProvider.notifier).setDefault(account.id),
              onDelete: () => _confirmDelete(context, ref, account),
            ),
        const SizedBox(height: AppSpacing.lg),
        const Text('Withdrawal history', style: AppTextStyles.title),
        const SizedBox(height: AppSpacing.sm),
        if (state.requests.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Text('No withdrawals yet.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          )
        else
          for (final request in state.requests) _RequestCard(request: request),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, PayoutAccount account) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove bank account?'),
        content: Text('${account.bankName} ${account.maskedNumber} will be removed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(proPayoutsControllerProvider.notifier).removeAccount(account.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account removed')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.balance, required this.onWithdraw});
  final PayoutBalance balance;
  final VoidCallback onWithdraw;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      color: AppColors.primary,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Available balance', style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.8))),
          const SizedBox(height: 4),
          Text(Formatters.money(balance.available, 'NGN'), style: AppTextStyles.headline1.copyWith(color: Colors.white)),
          const SizedBox(height: AppSpacing.sm),
          Row(
            children: [
              _BalanceChip(label: 'Pending', value: Formatters.money(balance.pending, 'NGN')),
              const SizedBox(width: AppSpacing.sm),
              _BalanceChip(label: 'Total earned', value: Formatters.money(balance.total, 'NGN')),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          FilledButton.icon(
            onPressed: onWithdraw,
            style: FilledButton.styleFrom(backgroundColor: Colors.white, foregroundColor: AppColors.primary),
            icon: const Icon(Icons.account_balance_wallet_outlined, size: 18),
            label: const Text('Withdraw'),
          ),
        ],
      ),
    );
  }
}

class _BalanceChip extends StatelessWidget {
  const _BalanceChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(10)),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: AppTextStyles.caption.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            Text(value, style: AppTextStyles.bodyMedium.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
          ],
        ),
      ),
    );
  }
}

class _AccountCard extends StatelessWidget {
  const _AccountCard({required this.account, required this.onDefault, required this.onDelete});
  final PayoutAccount account;
  final VoidCallback onDefault;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: AppColors.roseGold.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
            child: const Icon(Icons.account_balance_rounded, color: AppColors.primary, size: 20),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(account.bankName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                Text('${account.accountName} · ${account.maskedNumber}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                if (account.isDefault)
                  Text('Default account', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
          if (!account.isDefault)
            TextButton(onPressed: onDefault, child: const Text('Set default')),
          IconButton(
            onPressed: onDelete,
            icon: const Icon(Icons.delete_outline_rounded, size: 20, color: AppColors.textSecondary),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends StatelessWidget {
  const _RequestCard({required this.request});
  final Payout request;

  @override
  Widget build(BuildContext context) {
    final (color, label) = switch (request.status) {
      'PAID' => (AppColors.success, 'Paid'),
      'FAILED' || 'CANCELLED' => (AppColors.error, request.statusLabel),
      _ => (AppColors.warning, request.statusLabel),
    };
    return AppCard(
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(Formatters.money(request.amount, request.currency), style: AppTextStyles.title.copyWith(color: AppColors.primary)),
                if (request.accountName.isNotEmpty)
                  Text('To ${request.accountName}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                Text('${Formatters.date(request.createdAt)} ${Formatters.time(request.createdAt ?? DateTime.now())}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
            decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(12)),
            child: Text(label, style: AppTextStyles.caption.copyWith(color: color, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
  }
}

class AccountSheet extends ConsumerStatefulWidget {
  const AccountSheet({super.key});

  @override
  ConsumerState<AccountSheet> createState() => _AccountSheetState();
}

class _AccountSheetState extends ConsumerState<AccountSheet> {
  final _bankName = TextEditingController();
  final _bankCode = TextEditingController();
  final _accountNumber = TextEditingController();
  final _accountName = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _bankName.dispose();
    _bankCode.dispose();
    _accountNumber.dispose();
    _accountName.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_bankName.text.trim().isEmpty || _accountNumber.text.trim().isEmpty || _accountName.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Bank, account number and account name are required')));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(proPayoutsControllerProvider.notifier).addAccount({
        'bank_name': _bankName.text.trim(),
        'bank_code': _bankCode.text.trim(),
        'account_number': _accountNumber.text.trim(),
        'account_name': _accountName.text.trim(),
      });
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Bank account added')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Add bank account', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.md),
            TextField(controller: _bankName, decoration: const InputDecoration(labelText: 'Bank name')),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _bankCode, decoration: const InputDecoration(labelText: 'Bank code (optional)')),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _accountNumber,
              decoration: const InputDecoration(labelText: 'Account number'),
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(controller: _accountName, decoration: const InputDecoration(labelText: 'Account name')),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Add account', onPressed: _saving ? null : _save, loading: _saving),
          ],
        ),
      ),
    );
  }
}

class WithdrawSheet extends ConsumerStatefulWidget {
  const WithdrawSheet({super.key});

  @override
  ConsumerState<WithdrawSheet> createState() => _WithdrawSheetState();
}

class _WithdrawSheetState extends ConsumerState<WithdrawSheet> {
  final _amount = TextEditingController();
  String? _accountId;
  bool _saving = false;

  @override
  void dispose() {
    _amount.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final amount = double.tryParse(_amount.text) ?? 0;
    if (amount <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter an amount')));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(proPayoutsControllerProvider.notifier).request(amount: amount, accountId: _accountId);
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Withdrawal requested')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final accounts = ref.watch(proPayoutsControllerProvider).accounts;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('Withdraw funds', style: AppTextStyles.title),
          const SizedBox(height: AppSpacing.md),
          TextField(
            controller: _amount,
            decoration: const InputDecoration(labelText: 'Amount (NGN)'),
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          ),
          const SizedBox(height: AppSpacing.sm),
          DropdownButtonFormField<String>(
            initialValue: _accountId,
            decoration: const InputDecoration(labelText: 'Bank account'),
            items: [
              for (final a in accounts)
                DropdownMenuItem(value: a.id, child: Text('${a.bankName} · ${a.maskedNumber}', overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => setState(() => _accountId = v),
          ),
          const SizedBox(height: AppSpacing.md),
          AppButton(label: 'Request withdrawal', onPressed: _saving ? null : _save, loading: _saving),
        ],
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/deal.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../pro_controller.dart';

/// Professional deals: create promo codes and toggle them on/off.
class ProDealsTab extends ConsumerWidget {
  const ProDealsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(proDealsControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Row(
              children: [
                const Expanded(child: Text('Deals & promos', style: AppTextStyles.headline2)),
                AppButton(
                  label: 'New deal',
                  icon: Icons.add_rounded,
                  expanded: false,
                  onPressed: () => showGlameaSheet(context, child: const DealSheet()),
                ),
              ],
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(proDealsControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: _buildList(context, ref, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, ProListState<Deal> state) {
    if (state.status == ProListStatus.loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [SkeletonList(count: 4)],
      );
    }
    if (state.status == ProListStatus.error) {
      return ListView(
        children: [
          ErrorState(
            message: state.error ?? 'Could not load deals.',
            onRetry: () => ref.read(proDealsControllerProvider.notifier).refresh(),
          ),
        ],
      );
    }
    if (state.items.isEmpty) {
      return ListView(
        children: const [
          EmptyState(
            icon: Icons.local_offer_outlined,
            title: 'No deals yet',
            message: 'Create a promo code to attract more bookings.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _DealCard(
        deal: state.items[i],
        onToggle: (v) => ref.read(proDealsControllerProvider.notifier).toggle(state.items[i].id, v),
      ),
    );
  }
}

class _DealCard extends StatelessWidget {
  const _DealCard({required this.deal, required this.onToggle});
  final Deal deal;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 64,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: AppColors.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              deal.badgeLabel,
              style: AppTextStyles.title.copyWith(color: AppColors.primary, fontWeight: FontWeight.w800),
            ),
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(deal.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.title),
                const SizedBox(height: 2),
                Text('CODE: ${deal.code}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary, letterSpacing: 1)),
                if (deal.minOrderAmount > 0)
                  Text('Min order ${Formatters.money(deal.minOrderAmount, 'NGN')}', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                Text('Used ${deal.timesUsed} time(s)', style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
              ],
            ),
          ),
          Switch(value: deal.isActive, onChanged: onToggle),
        ],
      ),
    );
  }
}

class DealSheet extends ConsumerStatefulWidget {
  const DealSheet({super.key});

  @override
  ConsumerState<DealSheet> createState() => _DealSheetState();
}

class _DealSheetState extends ConsumerState<DealSheet> {
  final _name = TextEditingController();
  final _code = TextEditingController();
  final _value = TextEditingController();
  final _minOrder = TextEditingController();
  String _type = 'PERCENT';
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    _code.dispose();
    _value.dispose();
    _minOrder.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_name.text.trim().isEmpty || _value.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Name and discount value are required')));
      return;
    }
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      await ref.read(proDealsControllerProvider.notifier).create({
        'name': _name.text.trim(),
        'code': _code.text.trim().toUpperCase(),
        'discount_type': _type,
        'discount_value': double.tryParse(_value.text) ?? 0,
        'min_order_amount': double.tryParse(_minOrder.text) ?? 0,
      });
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Deal created')));
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
            const Text('New deal', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.md),
            TextField(
              controller: _name,
              decoration: const InputDecoration(labelText: 'Deal name'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _code,
              decoration: const InputDecoration(labelText: 'Promo code (optional)'),
              textCapitalization: TextCapitalization.characters,
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'PERCENT', label: Text('%')),
                      ButtonSegment(value: 'FIXED', label: Text('Fixed')),
                    ],
                    selected: {_type},
                    onSelectionChanged: (s) => setState(() => _type = s.first),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _value,
                    decoration: InputDecoration(labelText: _type == 'PERCENT' ? 'Discount %' : 'Discount amount (NGN)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    controller: _minOrder,
                    decoration: const InputDecoration(labelText: 'Min order (NGN)'),
                    keyboardType: TextInputType.number,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Create deal', onPressed: _saving ? null : _save, loading: _saving),
          ],
        ),
      ),
    );
  }
}

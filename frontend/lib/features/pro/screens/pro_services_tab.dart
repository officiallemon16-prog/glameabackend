import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/beauty_service.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../pro_controller.dart';

/// Professional services: CRUD on the studio's menu.
class ProServicesTab extends ConsumerWidget {
  const ProServicesTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(proServicesControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlameaPageHeader(
            title: 'My services',
            trailing: AppButton(
              label: 'Add service',
              icon: Icons.add_rounded,
              expanded: false,
              onPressed: () => showGlameaSheet(
                context,
                child: const ServiceSheet(service: null),
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(proServicesControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: _buildList(context, ref, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, ProListState<BeautyService> state) {
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
            message: state.error ?? 'Could not load services.',
            onRetry: () => ref.read(proServicesControllerProvider.notifier).refresh(),
          ),
        ],
      );
    }
    if (state.items.isEmpty) {
      return ListView(
        children: const [
          EmptyState(
            icon: Icons.content_cut_rounded,
            title: 'No services yet',
            message: 'Add your first service so customers can book you.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _ServiceCard(
        service: state.items[i],
        onEdit: () => showGlameaSheet(context, child: ServiceSheet(service: state.items[i])),
        onDelete: () => _confirmDelete(context, ref, state.items[i]),
        onToggle: () async {
          await ref
              .read(proServicesControllerProvider.notifier)
              .update(state.items[i].id, {'is_active': !state.items[i].isActive});
        },
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref, BeautyService service) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete service?'),
        content: Text('"${service.name}" will be removed from your menu.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: AppColors.error),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await ref.read(proServicesControllerProvider.notifier).remove(service.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Service deleted')));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      }
    }
  }
}

class _ServiceCard extends StatelessWidget {
  const _ServiceCard({required this.service, required this.onEdit, required this.onDelete, required this.onToggle});
  final BeautyService service;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(service.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.title),
              ),
              Switch(value: service.isActive, onChanged: (_) => onToggle()),
            ],
          ),
          if (service.description.isNotEmpty)
            Text(service.description, maxLines: 2, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          const SizedBox(height: AppSpacing.xs),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              _Pill(text: Formatters.money(service.basePrice, service.currency)),
              _Pill(text: '${service.durationMinutes} min'),
              if (service.homeServiceAvailable) const _Pill(text: 'Home service'),
              if (service.depositPercentage > 0) _Pill(text: 'Deposit ${service.depositPercentage.toStringAsFixed(0)}%'),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              TextButton.icon(onPressed: onDelete, icon: const Icon(Icons.delete_outline_rounded, size: 18), label: const Text('Delete')),
              TextButton.icon(onPressed: onEdit, icon: const Icon(Icons.edit_outlined, size: 18), label: const Text('Edit')),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 4),
      decoration: BoxDecoration(color: AppColors.softGrey, borderRadius: BorderRadius.circular(10)),
      child: Text(text, style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
    );
  }
}

class ServiceSheet extends ConsumerStatefulWidget {
  const ServiceSheet({super.key, this.service});
  final BeautyService? service;

  @override
  ConsumerState<ServiceSheet> createState() => _ServiceSheetState();
}

class _ServiceSheetState extends ConsumerState<ServiceSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _duration;
  late final TextEditingController _deposit;
  bool _homeService = false;
  bool _saving = false;

  bool get _isEdit => widget.service != null;

  @override
  void initState() {
    super.initState();
    final s = widget.service;
    _name = TextEditingController(text: s?.name ?? '');
    _description = TextEditingController(text: s?.description ?? '');
    _price = TextEditingController(text: s == null ? '' : s.basePrice.toStringAsFixed(0));
    _duration = TextEditingController(text: s == null ? '60' : '${s.durationMinutes}');
    _deposit = TextEditingController(text: s == null ? '0' : s.depositPercentage.toStringAsFixed(0));
    _homeService = s?.homeServiceAvailable ?? false;
  }

  @override
  void dispose() {
    _name.dispose();
    _description.dispose();
    _price.dispose();
    _duration.dispose();
    _deposit.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final payload = <String, dynamic>{
        'name': _name.text.trim(),
        'description': _description.text.trim(),
        'base_price': double.tryParse(_price.text) ?? 0,
        'duration_minutes': int.tryParse(_duration.text) ?? 60,
        'deposit_percentage': double.tryParse(_deposit.text) ?? 0,
        'home_service_available': _homeService,
      };
      final notifier = ref.read(proServicesControllerProvider.notifier);
      if (_isEdit) {
        await notifier.update(widget.service!.id, payload);
      } else {
        await notifier.create(payload);
      }
      navigator.pop();
      messenger.showSnackBar(SnackBar(content: Text(_isEdit ? 'Service updated' : 'Service added')));
    } catch (e) {
      messenger.removeCurrentSnackBar();
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_isEdit ? 'Edit service' : 'New service', style: AppTextStyles.title),
              const SizedBox(height: AppSpacing.md),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(labelText: 'Service name'),
                textInputAction: TextInputAction.next,
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Enter a name' : null,
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _description,
                decoration: const InputDecoration(labelText: 'Description', alignLabelWithHint: true),
                maxLines: 3,
                textInputAction: TextInputAction.newline,
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      controller: _price,
                      decoration: const InputDecoration(labelText: 'Price (NGN)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: TextFormField(
                      controller: _duration,
                      decoration: const InputDecoration(labelText: 'Duration (min)'),
                      keyboardType: TextInputType.number,
                      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                      validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              TextFormField(
                controller: _deposit,
                decoration: const InputDecoration(labelText: 'Deposit %'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              ),
              const SizedBox(height: AppSpacing.sm),
              SwitchListTile(
                value: _homeService,
                onChanged: (v) => setState(() => _homeService = v),
                title: const Text('Offer home service'),
                contentPadding: EdgeInsets.zero,
                dense: true,
              ),
              const SizedBox(height: AppSpacing.md),
              AppButton(
                label: _isEdit ? 'Save changes' : 'Add service',
                onPressed: _saving ? null : _save,
                loading: _saving,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

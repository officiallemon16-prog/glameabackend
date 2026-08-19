import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../models/availability.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_states.dart';
import '../pro_controller.dart';

/// Professional availability: weekly windows + one-off exceptions.
class ProAvailabilityTab extends ConsumerStatefulWidget {
  const ProAvailabilityTab({super.key});

  @override
  ConsumerState<ProAvailabilityTab> createState() => _ProAvailabilityTabState();
}

class _ProAvailabilityTabState extends ConsumerState<ProAvailabilityTab> {
  bool _saving = false;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(proAvailabilityControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GlameaPageHeader(
            title: 'Availability',
            trailing: AppButton(
              label: _saving ? 'Saving...' : 'Save',
              icon: Icons.save_outlined,
              height: 40,
              expanded: false,
              onPressed: _saving ? null : () => _save(context),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(proAvailabilityControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: _buildList(context, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, ProAvailabilityState state) {
    if (state.status == ProListStatus.loading) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.md),
        children: const [SkeletonList(count: 6)],
      );
    }
    if (state.status == ProListStatus.error) {
      return ListView(
        children: [
          ErrorState(
            message: state.error ?? 'Could not load availability.',
            onRetry: () => ref.read(proAvailabilityControllerProvider.notifier).refresh(),
          ),
        ],
      );
    }

    final byDay = <int, List<AvailabilityWindow>>{};
    for (final w in state.windows) {
      byDay.putIfAbsent(w.dayOfWeek, () => []).add(w);
    }

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      children: [
        const Text('Weekly hours', style: AppTextStyles.title),
        const SizedBox(height: AppSpacing.sm),
        for (var day = 0; day < 7; day++) _DayRow(day: day, windows: byDay[day] ?? const []),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            const Expanded(child: Text('Day offs', style: AppTextStyles.title)),
            IconButton(
              onPressed: () => showGlameaSheet(context, child: const ExceptionSheet()),
              icon: const Icon(Icons.add_rounded, color: AppColors.primary),
              tooltip: 'Add day off',
            ),
          ],
        ),
        if (state.exceptions.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text('No days off yet. Add one to block a specific date.', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary)),
          )
        else
          for (final e in state.exceptions)
            _ExceptionCard(exception: e),
      ],
    );
  }

  Future<void> _save(BuildContext context) async {
    final state = ref.read(proAvailabilityControllerProvider);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    try {
      final windows = [
        for (final w in state.windows)
          {
            'day_of_week': w.dayOfWeek,
            'start_minutes': w.startMinutes,
            'end_minutes': w.endMinutes,
            'is_active': w.isActive,
          },
      ];
      await ref.read(proAvailabilityControllerProvider.notifier).saveWindows(windows);
      messenger.showSnackBar(const SnackBar(content: Text('Availability saved')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

class _DayRow extends ConsumerWidget {
  const _DayRow({required this.day, required this.windows});
  final int day;
  final List<AvailabilityWindow> windows;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(width: 56, child: Text(dayOfWeekLabel(day), style: AppTextStyles.bodyMedium)),
          Expanded(
            child: windows.isEmpty
                ? Text('Unavailable', style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary))
                : Wrap(
                    spacing: AppSpacing.xs,
                    runSpacing: 4,
                    children: [
                      for (final w in windows)
                        _WindowChip(
                          window: w,
                          onTap: () => _editWindow(context, ref, w),
                        ),
                    ],
                  ),
          ),
          IconButton(
            onPressed: () => _addWindow(context, ref, day),
            icon: const Icon(Icons.add_circle_outline_rounded, size: 22, color: AppColors.primary),
            tooltip: 'Add hours',
          ),
        ],
      ),
    );
  }

  Future<void> _addWindow(BuildContext context, WidgetRef ref, int day) async {
    final start = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 9, minute: 0));
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(context: context, initialTime: const TimeOfDay(hour: 17, minute: 0));
    if (end == null || !context.mounted) return;
    final notifier = ref.read(proAvailabilityControllerProvider.notifier);
    final current = ref.read(proAvailabilityControllerProvider);
    notifier.localAdd(day, start.hour * 60 + start.minute, end.hour * 60 + end.minute, current.windows);
  }

  Future<void> _editWindow(BuildContext context, WidgetRef ref, AvailabilityWindow w) async {
    final current = ref.read(proAvailabilityControllerProvider);
    final startMinutes = w.startMinutes;
    final initialStart = TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);
    final endMinutes = w.endMinutes;
    final initialEnd = TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);

    final start = await showTimePicker(context: context, initialTime: initialStart);
    if (start == null || !context.mounted) return;
    final end = await showTimePicker(context: context, initialTime: initialEnd);
    if (end == null || !context.mounted) return;
    ref.read(proAvailabilityControllerProvider.notifier).localUpdate(
          w.id,
          start.hour * 60 + start.minute,
          end.hour * 60 + end.minute,
          current.windows,
        );
  }
}

class _WindowChip extends StatelessWidget {
  const _WindowChip({required this.window, required this.onTap});
  final AvailabilityWindow window;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 6),
        decoration: BoxDecoration(
          color: window.isActive ? AppColors.primary.withValues(alpha: 0.08) : AppColors.softGrey,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: window.isActive ? AppColors.primary.withValues(alpha: 0.35) : Colors.transparent),
        ),
        child: Text(
          '${window.startLabel} – ${window.endLabel}',
          style: AppTextStyles.caption.copyWith(
            color: window.isActive ? AppColors.primary : AppColors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

class _ExceptionCard extends ConsumerWidget {
  const _ExceptionCard({required this.exception});
  final AvailabilityException exception;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(exception.isBlock ? Icons.event_busy_rounded : Icons.event_available_rounded, color: exception.isBlock ? AppColors.error : AppColors.success, size: 20),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              '${exception.date}${exception.note.isNotEmpty ? ' · ${exception.note}' : ''}',
              style: AppTextStyles.bodyMedium,
            ),
          ),
          IconButton(
            onPressed: () => ref.read(proAvailabilityControllerProvider.notifier).removeException(exception.id),
            icon: const Icon(Icons.close_rounded, size: 20, color: AppColors.textSecondary),
            tooltip: 'Remove',
          ),
        ],
      ),
    );
  }
}

class ExceptionSheet extends ConsumerStatefulWidget {
  const ExceptionSheet({super.key});

  @override
  ConsumerState<ExceptionSheet> createState() => _ExceptionSheetState();
}

class _ExceptionSheetState extends ConsumerState<ExceptionSheet> {
  DateTime _date = DateTime.now();
  final _note = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date,
      firstDate: DateTime.now().subtract(const Duration(days: 1)),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => _date = picked);
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    try {
      final date = '${_date.year.toString().padLeft(4, '0')}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}';
      await ref.read(proAvailabilityControllerProvider.notifier).addException({
        'date': date,
        'is_available': false,
        'note': _note.text.trim(),
      });
      navigator.pop();
      messenger.showSnackBar(const SnackBar(content: Text('Day off added')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Add day off', style: AppTextStyles.title),
            const SizedBox(height: AppSpacing.md),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.calendar_month_outlined),
              title: const Text('Date'),
              subtitle: Text('${_date.year}-${_date.month.toString().padLeft(2, '0')}-${_date.day.toString().padLeft(2, '0')}'),
              onTap: _pickDate,
            ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              controller: _note,
              decoration: const InputDecoration(labelText: 'Note (optional)'),
              textInputAction: TextInputAction.done,
            ),
            const SizedBox(height: AppSpacing.md),
            AppButton(label: 'Add day off', onPressed: _saving ? null : _save, loading: _saving),
          ],
        ),
      ),
    );
  }
}

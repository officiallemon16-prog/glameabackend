import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_dimens.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/location/location_service.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_button.dart';
import '../../../shared/widgets/app_text_field.dart';
import '../../discovery/discovery_controller.dart';
import '../data/pro_api.dart';
import '../pro_controller.dart';

/// Multi-step onboarding wizard for new professionals.
/// Guides the user through profile setup, services, and availability
/// with a visual progress bar.
class ProOnboardingScreen extends ConsumerStatefulWidget {
  const ProOnboardingScreen({super.key});

  @override
  ConsumerState<ProOnboardingScreen> createState() =>
      _ProOnboardingScreenState();
}

class _ProOnboardingScreenState extends ConsumerState<ProOnboardingScreen> {
  int _step = 0;
  static const _totalSteps = 6;

  // Step 1: Business info
  final _businessName = TextEditingController();
  final _displayName = TextEditingController();
  final _bio = TextEditingController();
  String? _selectedCategoryId;
  int? _experienceYears;

  // Step 2: Location
  final _city = TextEditingController();
  final _address = TextEditingController();
  bool _homeService = false;

  // Step 3: Services
  final List<_ServiceEntry> _services = [_ServiceEntry()];

  // Step 4: Availability
  Map<int, _TimeSlot> _availability = {};

  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _businessName.dispose();
    _displayName.dispose();
    _bio.dispose();
    _city.dispose();
    _address.dispose();
    for (final s in _services) {
      s.dispose();
    }
    super.dispose();
  }

  void _next() {
    if (_step < _totalSteps - 1) {
      setState(() => _step++);
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
    }
  }

  bool _canProceed() {
    switch (_step) {
      case 0:
        return _businessName.text.trim().isNotEmpty && _selectedCategoryId != null;
      case 1:
        return _city.text.trim().isNotEmpty;
      case 2:
        return _services.any(
          (s) => s.name.text.trim().isNotEmpty && s.price.text.trim().isNotEmpty,
        );
      case 3:
        return _availability.isNotEmpty;
      default:
        return true;
    }
  }

  Future<void> _submit() async {
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final proApi = ref.read(proApiProvider);

      await proApi.createMyProfile({
        'business_name': _businessName.text.trim(),
        'display_name': _displayName.text.trim(),
        'bio': _bio.text.trim(),
        'city': _city.text.trim(),
        'address_line': _address.text.trim(),
        if (_selectedCategoryId != null) 'category_id': _selectedCategoryId,
        if (_experienceYears != null) 'experience_years': _experienceYears,
        'home_service_enabled': _homeService,
      });

      // Step 2: Create services
      for (final s in _services) {
        final name = s.name.text.trim();
        if (name.isEmpty) continue;
        final price = double.tryParse(s.price.text.trim()) ?? 0;
        final duration = int.tryParse(s.duration.text.trim()) ?? 60;
        final deposit = double.tryParse(s.depositPercent.text.trim()) ?? 50;
        await proApi.createService({
          'name': name,
          'description': s.description.text.trim(),
          'base_price': price,
          'currency': 'NGN',
          'duration_minutes': duration,
          'deposit_percentage': deposit.clamp(0, 100),
        });
      }

      // Step 3: Save availability
      if (_availability.isNotEmpty) {
        final windows = <Map<String, dynamic>>[];
        _availability.forEach((day, slot) {
          if (slot.open != null && slot.close != null) {
            windows.add({
              'day_of_week': day,
              'start_time': slot.open!,
              'end_time': slot.close!,
            });
          }
        });
        if (windows.isNotEmpty) {
          await proApi.saveWindows(windows);
        }
      }

      // Refresh profile in controller
      await ref.read(proProfileControllerProvider.notifier).refresh();

      if (mounted) {
        setState(() => _step = _totalSteps - 1);
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = e.toString();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      appBar: GlameaAppBar(
        title: _step == _totalSteps - 1 ? '' : 'Set up your studio',
        showBack: false,
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Progress bar (hidden on welcome and done steps)
            if (_step > 0 && _step < _totalSteps - 1)
              _ProgressBar(current: _step, total: _totalSteps - 2),

            // Pages
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 250),
                switchInCurve: Curves.easeIn,
                switchOutCurve: Curves.easeOut,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: child,
                ),
                child: ColoredBox(
                  color: AppColors.surface,
                  key: ValueKey<int>(_step),
                  child: _buildCurrentStep(),
                ),
              ),
            ),

            // Bottom buttons (hidden on welcome and done steps)
            if (_step > 0 && _step < _totalSteps - 1)
              _buildBottomBar(),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.lg,
      ),
      decoration: const BoxDecoration(
        color: AppColors.white,
        border: Border(top: BorderSide(color: AppColors.borderSubtle)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_error != null) ...[
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.error.withValues(alpha: 0.3)),
              ),
              child: Text(
                _error!,
                style: AppTextStyles.bodyMedium.copyWith(color: AppColors.error),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          Row(
            children: [
              if (_step > 1) ...[
                Expanded(
                  child: AppButton(
                    label: 'Back',
                    variant: AppButtonVariant.outline,
                    onPressed: _saving ? null : _back,
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Expanded(
                child: _step == _totalSteps - 2
                    ? AppButton(
                        label: _saving ? 'Saving...' : 'Finish setup',
                        icon: Icons.check_rounded,
                        loading: _saving,
                        onPressed: _saving || !_canProceed() ? null : _submit,
                      )
                    : AppButton(
                        label: 'Continue',
                        icon: Icons.arrow_forward_rounded,
                        onPressed: _canProceed() ? _next : null,
                      ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildCurrentStep() {
    switch (_step) {
      case 0:
        return KeyedSubtree(key: const ValueKey(0), child: _WelcomeStep(onGetStarted: _next));
      case 1:
        return KeyedSubtree(
          key: const ValueKey(1),
          child: _BusinessInfoStep(
            businessName: _businessName,
            displayName: _displayName,
            bio: _bio,
            selectedCategoryId: _selectedCategoryId,
            experienceYears: _experienceYears,
            onCategoryChanged: (id) => setState(() => _selectedCategoryId = id),
            onExperienceChanged: (y) => setState(() => _experienceYears = y),
          ),
        );
      case 2:
        return KeyedSubtree(
          key: const ValueKey(2),
          child: _LocationStep(
            city: _city,
            address: _address,
            homeService: _homeService,
            onHomeServiceChanged: (v) => setState(() => _homeService = v),
          ),
        );
      case 3:
        return KeyedSubtree(
          key: const ValueKey(3),
          child: _ServicesStep(
            services: _services,
            onAdd: () => setState(() => _services.add(_ServiceEntry())),
            onRemove: (i) => setState(() => _services.removeAt(i)),
          ),
        );
      case 4:
        return KeyedSubtree(
          key: const ValueKey(4),
          child: _AvailabilityStep(
            availability: _availability,
            onChanged: (day, slot) => setState(() => _availability[day] = slot),
          ),
        );
      case 5:
        return KeyedSubtree(
          key: const ValueKey(5),
          child: _DoneStep(onFinish: () => context.go(AppRoutes.pro)),
        );
      default:
        return const SizedBox.shrink();
    }
  }
}

// ---------------------------------------------------------------------------
// Progress Bar
// ---------------------------------------------------------------------------

class _ProgressBar extends StatelessWidget {
  const _ProgressBar({required this.current, required this.total});
  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg, AppSpacing.xs, AppSpacing.lg, AppSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Step $current of $total',
                style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
              ),
              Text(
                '${((current / total) * 100).round()}%',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xxs),
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: current / total,
              minHeight: 4,
              backgroundColor: AppColors.softGrey,
              valueColor: const AlwaysStoppedAnimation(AppColors.primary),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 1: Welcome
// ---------------------------------------------------------------------------

class _WelcomeStep extends StatelessWidget {
  const _WelcomeStep({required this.onGetStarted});
  final VoidCallback onGetStarted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 100,
            height: 100,
            decoration: const BoxDecoration(
              color: AppColors.primary,
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.storefront_rounded,
              color: Colors.white,
              size: 48,
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'Welcome to your\nstudio setup',
            textAlign: TextAlign.center,
            style: AppTextStyles.headline1.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Create your professional profile, add your services, and set your availability — all in a few easy steps.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            label: 'Get started',
            icon: Icons.arrow_forward_rounded,
            onPressed: onGetStarted,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 2: Business Info
// ---------------------------------------------------------------------------

class _BusinessInfoStep extends ConsumerWidget {
  const _BusinessInfoStep({
    required this.businessName,
    required this.displayName,
    required this.bio,
    required this.selectedCategoryId,
    required this.experienceYears,
    required this.onCategoryChanged,
    required this.onExperienceChanged,
  });

  final TextEditingController businessName;
  final TextEditingController displayName;
  final TextEditingController bio;
  final String? selectedCategoryId;
  final int? experienceYears;
  final ValueChanged<String?> onCategoryChanged;
  final ValueChanged<int?> onExperienceChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final categoriesAsync = ref.watch(categoriesProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'About your business',
            style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Tell customers what makes you special.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          AppTextField(
            controller: businessName,
            hintText: 'Business name *',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: displayName,
            hintText: 'Display name (optional)',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: bio,
            hintText: 'Short bio',
            maxLines: 3,
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          // Category dropdown
          categoriesAsync.when(
            data: (categories) => DropdownButtonFormField<String>(
              initialValue: selectedCategoryId,
              decoration: InputDecoration(
                hintText: 'Category *',
                filled: true,
                fillColor: AppColors.white,
                border: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                  borderRadius: BorderRadius.circular(8),
                ),
                enabledBorder: OutlineInputBorder(
                  borderSide: const BorderSide(color: AppColors.borderSubtle),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              items: categories
                  .map((c) => DropdownMenuItem(value: c.id, child: Text(c.name)))
                  .toList(),
              onChanged: onCategoryChanged,
            ),
            loading: () => const SizedBox(
              height: AppDimens.inputHeight,
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (_, __) => const SizedBox.shrink(),
          ),
          const SizedBox(height: AppSpacing.md),
          // Experience years
          DropdownButtonFormField<int>(
            initialValue: experienceYears,
            decoration: InputDecoration(
              hintText: 'Years of experience',
              filled: true,
              fillColor: AppColors.white,
              border: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(8),
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: const BorderSide(color: AppColors.borderSubtle),
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            items: List.generate(21, (i) => i)
                .map((y) => DropdownMenuItem(
                      value: y,
                      child: Text(y == 0 ? 'Less than 1 year' : '$y years'),
                    ))
                .toList(),
            onChanged: onExperienceChanged,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 3: Location
// ---------------------------------------------------------------------------

class _LocationStep extends ConsumerStatefulWidget {
  const _LocationStep({
    required this.city,
    required this.address,
    required this.homeService,
    required this.onHomeServiceChanged,
  });

  final TextEditingController city;
  final TextEditingController address;
  final bool homeService;
  final ValueChanged<bool> onHomeServiceChanged;

  @override
  ConsumerState<_LocationStep> createState() => _LocationStepState();
}

class _LocationStepState extends ConsumerState<_LocationStep> {
  bool _locating = false;

  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final coords = await LocationService.requestWithUI(context);
      if (coords != null && mounted) {
        // We have coordinates; fill the city field with a fallback if empty.
        // In a real app you'd reverse-geocode, but for now use coordinates
        // as a placeholder so the backend has something to work with.
        if (widget.city.text.trim().isEmpty) {
          widget.city.text = '${coords.latitude.toStringAsFixed(4)}, ${coords.longitude.toStringAsFixed(4)}';
        }
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Location detected.')),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Where are you located?',
            style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Help customers find you.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          // Auto-detect location button
          GestureDetector(
            onTap: _locating ? null : _useCurrentLocation,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (_locating)
                    const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: AppColors.primary,
                      ),
                    )
                  else
                    const Icon(Icons.my_location_rounded,
                        color: AppColors.primary, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    _locating ? 'Detecting location...' : 'Use my current location',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: widget.city,
            hintText: 'City *',
            textInputAction: TextInputAction.next,
          ),
          const SizedBox(height: AppSpacing.md),
          AppTextField(
            controller: widget.address,
            hintText: 'Studio address (optional)',
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: AppSpacing.lg),
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: Text(
              'Home service',
              style: AppTextStyles.body.copyWith(color: AppColors.textPrimary),
            ),
            subtitle: Text(
              'I can travel to customers',
              style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
            ),
            value: widget.homeService,
            onChanged: widget.onHomeServiceChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 4: Services
// ---------------------------------------------------------------------------

class _ServiceEntry {
  final name = TextEditingController();
  final description = TextEditingController();
  final price = TextEditingController();
  final duration = TextEditingController(text: '60');
  final depositPercent = TextEditingController(text: '50');

  void dispose() {
    name.dispose();
    description.dispose();
    price.dispose();
    duration.dispose();
    depositPercent.dispose();
  }
}

class _ServicesStep extends StatelessWidget {
  const _ServicesStep({
    required this.services,
    required this.onAdd,
    required this.onRemove,
  });

  final List<_ServiceEntry> services;
  final VoidCallback onAdd;
  final ValueChanged<int> onRemove;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Add your services',
            style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'Add at least one service so customers can book you.',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...List.generate(services.length, (i) {
            final s = services[i];
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.lg),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.borderSubtle),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Service ${i + 1}',
                          style: AppTextStyles.bodyMedium.copyWith(
                            fontWeight: FontWeight.w600,
                            color: AppColors.textPrimary,
                          ),
                        ),
                        if (services.length > 1)
                          IconButton(
                            icon: const Icon(Icons.remove_circle_outline,
                                color: AppColors.error, size: 22),
                            onPressed: () => onRemove(i),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      controller: s.name,
                      hintText: 'Service name *',
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      controller: s.description,
                      hintText: 'Description (optional)',
                      maxLines: 2,
                      textInputAction: TextInputAction.next,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: AppTextField(
                            controller: s.price,
                            hintText: 'Price (NGN) *',
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: AppTextField(
                            controller: s.duration,
                            hintText: 'Duration (min)',
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.next,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    AppTextField(
                      controller: s.depositPercent,
                      hintText: 'Deposit %',
                      keyboardType: TextInputType.number,
                    ),
                  ],
                ),
              ),
            );
          }),
          // Add service button
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.primary.withValues(alpha: 0.2),
                  style: BorderStyle.solid,
                ),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle_outline,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: AppSpacing.xs),
                  Text(
                    'Add another service',
                    style: AppTextStyles.bodyMedium.copyWith(
                      color: AppColors.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 5: Availability
// ---------------------------------------------------------------------------

class _TimeSlot {
  _TimeSlot({this.open, this.close});
  String? open;
  String? close;
}

class _AvailabilityStep extends StatefulWidget {
  const _AvailabilityStep({
    required this.availability,
    required this.onChanged,
  });

  final Map<int, _TimeSlot> availability;
  final void Function(int day, _TimeSlot slot) onChanged;

  @override
  State<_AvailabilityStep> createState() => _AvailabilityStepState();
}

class _AvailabilityStepState extends State<_AvailabilityStep> {
  static const _dayNames = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday',
    'Friday', 'Saturday', 'Sunday',
  ];

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Set your hours',
            style: AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            'When are you available for bookings?',
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.lg),
          ...List.generate(7, (i) {
            final slot = widget.availability[i];
            final isEnabled = slot != null;
            return Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md, vertical: AppSpacing.xs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: isEnabled
                        ? AppColors.primary.withValues(alpha: 0.3)
                        : AppColors.borderSubtle,
                  ),
                ),
                child: Row(
                  children: [
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: () {
                          if (isEnabled) {
                            widget.onChanged(i, _TimeSlot());
                          } else {
                            widget.onChanged(i,
                                _TimeSlot(open: '09:00', close: '17:00'));
                          }
                          setState(() {});
                        },
                        child: Row(
                          children: [
                            Icon(
                              isEnabled
                                  ? Icons.check_circle_rounded
                                  : Icons.radio_button_unchecked,
                              color: isEnabled
                                  ? AppColors.primary
                                  : AppColors.textMuted,
                              size: 20,
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            Text(
                              _dayNames[i].substring(0, 3),
                              style: AppTextStyles.bodyMedium.copyWith(
                                color: isEnabled
                                    ? AppColors.textPrimary
                                    : AppColors.textMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    if (isEnabled) ...[
                      Expanded(
                        flex: 3,
                        child: _TimePicker(
                          label: 'Open',
                          value: slot.open ?? '09:00',
                          onChanged: (v) {
                            widget.onChanged(i, _TimeSlot(open: v, close: slot.close));
                            setState(() {});
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                        child: Text(
                          'to',
                          style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textMuted),
                        ),
                      ),
                      Expanded(
                        flex: 3,
                        child: _TimePicker(
                          label: 'Close',
                          value: slot.close ?? '17:00',
                          onChanged: (v) {
                            widget.onChanged(i, _TimeSlot(open: slot.open, close: v));
                            setState(() {});
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

class _TimePicker extends StatelessWidget {
  const _TimePicker({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String value;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final parts = value.split(':');
        final initial = TimeOfDay(
          hour: int.tryParse(parts[0]) ?? 9,
          minute: int.tryParse(parts.length > 1 ? parts[1] : '0') ?? 0,
        );
        final picked = await showTimePicker(
          context: context,
          initialTime: initial,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(alwaysUse24HourFormat: true),
            child: child!,
          ),
        );
        if (picked != null) {
          onChanged(
            '${picked.hour.toString().padLeft(2, '0')}:${picked.minute.toString().padLeft(2, '0')}',
          );
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.softGrey,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          value,
          style: AppTextStyles.bodyMedium.copyWith(
            color: AppColors.textPrimary,
            fontWeight: FontWeight.w500,
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step 6: Done
// ---------------------------------------------------------------------------

class _DoneStep extends StatelessWidget {
  const _DoneStep({required this.onFinish});
  final VoidCallback onFinish;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSpacing.xl),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0.4, end: 1),
            duration: const Duration(milliseconds: 600),
            curve: Curves.elasticOut,
            child: Container(
              width: 96,
              height: 96,
              decoration: const BoxDecoration(
                color: AppColors.success,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_rounded, color: Colors.white, size: 48),
            ),
            builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
          ),
          const SizedBox(height: AppSpacing.xl),
          Text(
            'You\'re all set!',
            style: AppTextStyles.headline1.copyWith(color: AppColors.textPrimary),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'Your studio is live. Customers can now discover and book your services.',
            textAlign: TextAlign.center,
            style: AppTextStyles.body.copyWith(color: AppColors.textSecondary),
          ),
          const SizedBox(height: AppSpacing.xxl),
          AppButton(
            label: 'Go to my studio',
            icon: Icons.storefront_rounded,
            onPressed: onFinish,
          ),
        ],
      ),
    );
  }
}

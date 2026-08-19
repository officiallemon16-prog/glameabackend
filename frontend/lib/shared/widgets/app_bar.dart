import 'package:flutter/material.dart';

import '../../app/theme/app_colors.dart';
import '../../app/theme/app_dimens.dart';
import '../../app/theme/app_spacing.dart';
import '../../app/theme/app_typography.dart';

/// Glamea app bar - cream background, oxblood title, optional back.
class GlameaAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlameaAppBar({
    super.key,
    this.title,
    this.titleWidget,
    this.actions,
    this.showBack = true,
    this.bottom,
    this.centerTitle = false,
  });

  final String? title;

  /// Arbitrary widget to render as the app bar title (e.g. an avatar + name).
  /// Takes precedence over [title].
  final Widget? titleWidget;
  final List<Widget>? actions;
  final bool showBack;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + (bottom?.preferredSize.height ?? 0));

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: AppColors.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0.5,
      centerTitle: centerTitle,
      automaticallyImplyLeading: showBack && Navigator.of(context).canPop(),
      title: titleWidget ??
          (title != null
              ? Text(title!, style: AppTextStyles.title.copyWith(color: AppColors.textPrimary))
              : null),
      actions: actions,
      bottom: bottom,
      iconTheme: const IconThemeData(color: AppColors.primary),
    );
  }
}

/// Pinned page-level header (top nav) used by every shell tab: title with an
/// optional subtitle and trailing actions, on the cream surface with a subtle
/// bottom rule so it reads as a clean navigation bar. With [centerTitle] the
/// title sits centered between an optional [leading] and [trailing] action.
class GlameaPageHeader extends StatelessWidget {
  const GlameaPageHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.centerTitle = false,
    this.titleStyle,
  });

  final String title;
  final String? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool centerTitle;
  final TextStyle? titleStyle;

  Widget _title(BuildContext context) {
    return Column(
      crossAxisAlignment: centerTitle ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: titleStyle ?? AppTextStyles.headline2.copyWith(color: AppColors.textPrimary),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 2),
          Text(
            subtitle!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.bodyMedium.copyWith(color: AppColors.textSecondary),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(bottom: BorderSide(color: AppColors.borderSubtle)),
      ),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.sm,
      ),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: AppSpacing.xs),
          ],
          Expanded(
            child: centerTitle
                ? Center(child: _title(context))
                : _title(context),
          ),
          if (trailing != null) ...[
            const SizedBox(width: AppSpacing.sm),
            trailing!,
          ],
        ],
      ),
    );
  }
}

/// Section header used across tabs and detail screens: an optional subtitle
/// plus either a trailing widget or a "See all" style action button.
class SectionHeader extends StatelessWidget {
  const SectionHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.actionLabel,
    this.onAction,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
          AppSpacing.md, AppSpacing.lg, AppSpacing.md, AppSpacing.sm),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style:
                      AppTextStyles.title.copyWith(color: AppColors.textPrimary),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption
                        .copyWith(color: AppColors.textSecondary),
                  ),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
          if (actionLabel != null && onAction != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.primary,
                padding: EdgeInsets.zero,
                minimumSize: const Size(0, AppDimens.minTouchTarget),
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// Modal bottom sheet with the Glamea styling.
Future<T?> showGlameaSheet<T>(BuildContext context, {required Widget child, bool isScrollControlled = true}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: isScrollControlled,
    backgroundColor: AppColors.surface,
    useSafeArea: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: child,
    ),
  );
}

/// Sheet header with grab handle + title + close.
class SheetHeader extends StatelessWidget {
  const SheetHeader({super.key, required this.title, this.onClose});

  final String title;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          width: 40,
          height: 4,
          margin: const EdgeInsets.only(top: AppSpacing.sm, bottom: AppSpacing.sm),
          decoration: BoxDecoration(
            color: AppColors.borderSubtle,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        Row(
          children: [
            const SizedBox(width: AppSpacing.lg),
            Expanded(
              child: Text(title, style: AppTextStyles.title.copyWith(color: AppColors.textPrimary)),
            ),
            IconButton(
              onPressed: onClose ?? () => Navigator.of(context).pop(),
              icon: const Icon(Icons.close, color: AppColors.textSecondary),
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
      ],
    );
  }
}

/// Bottom navigation with the Glamea palette.
class GlameaNavBar extends StatelessWidget {
  const GlameaNavBar({
    super.key,
    required this.currentIndex,
    required this.onDestinationSelected,
    this.messagesUnread = 0,
  });

  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final int messagesUnread;

  List<NavigationDestination> _buildDestinations() {
    return [
      const NavigationDestination(
        icon: Icon(Icons.home_outlined),
        selectedIcon: Icon(Icons.home_rounded),
        label: 'Home',
      ),
      const NavigationDestination(
        icon: Icon(Icons.explore_outlined),
        selectedIcon: Icon(Icons.explore_rounded),
        label: 'Discover',
      ),
      const NavigationDestination(
        icon: Icon(Icons.calendar_month_outlined),
        selectedIcon: Icon(Icons.calendar_month),
        label: 'Bookings',
      ),
      NavigationDestination(
        icon: Badge.count(
          count: messagesUnread,
          isLabelVisible: messagesUnread > 0,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.chat_bubble_outline_rounded),
        ),
        selectedIcon: Badge.count(
          count: messagesUnread,
          isLabelVisible: messagesUnread > 0,
          backgroundColor: AppColors.primary,
          child: const Icon(Icons.chat_bubble_rounded),
        ),
        label: 'Messages',
      ),
      const NavigationDestination(
        icon: Icon(Icons.person_outline_rounded),
        selectedIcon: Icon(Icons.person_rounded),
        label: 'Profile',
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    return NavigationBar(
      selectedIndex: currentIndex,
      onDestinationSelected: onDestinationSelected,
      backgroundColor: AppColors.white,
      indicatorColor: AppColors.roseGold.withValues(alpha: 0.25),
      surfaceTintColor: Colors.transparent,
      height: 68,
      labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
      destinations: _buildDestinations(),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router/app_router.dart';
import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../models/conversation.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../messaging_controller.dart';

/// Messages tab (customer): the user's conversation list.
class MessagesTab extends ConsumerStatefulWidget {
  const MessagesTab({super.key});

  @override
  ConsumerState<MessagesTab> createState() => _MessagesTabState();
}

class _MessagesTabState extends ConsumerState<MessagesTab> {
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(conversationsControllerProvider);
    final userId = ref.watch(authControllerProvider).user?.id ?? '';

    return SafeArea(
      child: Column(
        children: [
          GlameaPageHeader(
            title: 'Messages',
            trailing: state.status == ConversationsStatus.ready
                ? IconButton(
                    onPressed: () => setState(() {
                      _searching = !_searching;
                      if (!_searching) {
                        _searchCtrl.clear();
                        _query = '';
                      }
                    }),
                    icon: Icon(
                      _searching ? Icons.close_rounded : Icons.search_rounded,
                      color: AppColors.textPrimary,
                    ),
                    tooltip: _searching ? 'Close search' : 'Search conversations',
                  )
                : null,
          ),
          if (_searching)
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.sm),
              child: TextField(
                controller: _searchCtrl,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                decoration: InputDecoration(
                  hintText: 'Search by name or service…',
                  isDense: true,
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  prefixIconConstraints: const BoxConstraints(minWidth: 36),
                  suffixIcon: _query.isNotEmpty
                      ? IconButton(
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _query = '');
                          },
                          icon: const Icon(Icons.clear_rounded, size: 18),
                        )
                      : null,
                ),
                onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              ),
            ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(conversationsControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: switch (state.status) {
                ConversationsStatus.loading => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.all(AppSpacing.md),
                    children: const [SkeletonList(count: 6)],
                  ),
                ConversationsStatus.error => ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      SizedBox(
                        height: 400,
                        child: ErrorState(
                          message: state.error ?? 'Could not load your messages.',
                          onRetry: () => ref.read(conversationsControllerProvider.notifier).refresh(),
                        ),
                      ),
                    ],
                  ),
                ConversationsStatus.ready => _ConversationList(
                    conversations: state.conversations,
                    userId: userId,
                    query: _query,
                  ),
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _ConversationList extends ConsumerWidget {
  const _ConversationList({required this.conversations, required this.userId, this.query = ''});

  final List<Conversation> conversations;
  final String userId;
  final String query;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filtered = query.isEmpty
        ? conversations
        : conversations.where((c) {
            final name = c.otherName(userId).toLowerCase();
            final service = c.serviceName.toLowerCase();
            final preview = c.lastMessage.toLowerCase();
            return name.contains(query) || service.contains(query) || preview.contains(query);
          }).toList();

    if (filtered.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          EmptyState(
            icon: query.isNotEmpty ? Icons.search_off_rounded : Icons.chat_bubble_outline_rounded,
            title: query.isNotEmpty ? 'No matches' : 'No messages yet',
            message: query.isNotEmpty
                ? 'No conversations match "$query". Try a different search.'
                : 'When you book an artist, you can chat with them here.',
          ),
        ],
      );
    }

    return ListView.separated(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: filtered.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (context, index) {
        final conversation = filtered[index];
        final otherName = conversation.otherName(userId);
        return _ConversationTile(
          conversation: conversation,
          otherName: otherName,
          userId: userId,
          onTap: () async {
            await context.push(AppRoutes.chatFor(conversation.bookingId));
            ref.read(conversationsControllerProvider.notifier).refresh();
          },
        );
      },
    );
  }
}

class _ConversationTile extends StatelessWidget {
  const _ConversationTile({
    required this.conversation,
    required this.otherName,
    required this.userId,
    required this.onTap,
  });

  final Conversation conversation;
  final String otherName;
  final String userId;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final lastMessageAt = conversation.lastMessageAt;
    final hasPreview = conversation.lastMessage.isNotEmpty;
    final isUnread =
        conversation.unreadCount > 0 && conversation.lastMessageSenderId != userId;
    final unreadLabel = conversation.unreadCount > 99 ? '99+' : '${conversation.unreadCount}';
    final subtitle = [
      if (conversation.serviceName.isNotEmpty) conversation.serviceName,
      if (hasPreview) conversation.lastMessage,
    ].join('  •  ');

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
              AppAvatar(name: otherName, url: conversation.otherAvatarUrl(userId), radius: 24),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            otherName.isEmpty ? 'Glamea professional' : otherName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyMedium.copyWith(
                              color: AppColors.textPrimary,
                              fontWeight: isUnread ? FontWeight.w800 : FontWeight.w700,
                            ),
                          ),
                        ),
                        if (lastMessageAt != null)
                          Text(
                            Formatters.relativeTime(lastMessageAt),
                            style: AppTextStyles.caption.copyWith(
                              color: isUnread ? AppColors.primary : AppColors.textMuted,
                              fontWeight: isUnread ? FontWeight.w700 : FontWeight.w400,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xxs),
                    Text(
                      subtitle.isEmpty ? 'Start a conversation' : subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.bodyMedium.copyWith(
                        color: isUnread ? AppColors.textPrimary : AppColors.textSecondary,
                        fontWeight: isUnread ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              if (isUnread)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  constraints: const BoxConstraints(minWidth: 20),
                  alignment: Alignment.center,
                  child: Text(
                    unreadLabel,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.white,
                      fontWeight: FontWeight.w700,
                      fontSize: 11,
                    ),
                  ),
                )
              else
                const Icon(Icons.chevron_right_rounded, color: AppColors.textMuted),
            ],
          ),
        ),
      ),
    );
  }
}

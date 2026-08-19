import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../features/auth/auth_controller.dart';
import '../../../features/location/location_map_screen.dart';
import '../../../features/location/location_picker_screen.dart';
import '../../../features/media/media_controller.dart';
import '../../../models/conversation.dart';
import '../../../models/message.dart';
import '../../../shared/widgets/app_bar.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../calls/call_controller.dart';
import '../messaging_controller.dart';

/// Chat screen for one booking: bubbles, polling refresh and send.
class ChatScreen extends ConsumerStatefulWidget {
  const ChatScreen({super.key, required this.bookingId});

  final String bookingId;

  @override
  ConsumerState<ChatScreen> createState() => _ChatScreenState();
}

class _PendingImage {
  const _PendingImage({required this.xFile, required this.bytes});
  final XFile xFile;
  final Uint8List bytes;
}

class _ChatScreenState extends ConsumerState<ChatScreen> {
  final _input = TextEditingController();
  final List<_PendingImage> _pendingImages = [];
  bool _showEmoji = false;

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = messagesControllerProvider(widget.bookingId);
    final state = ref.watch(provider);
    final userId = ref.watch(authControllerProvider).user?.id ?? '';

    ref.listen(provider.select((s) => s.sendError), (previous, next) {
      if (next != null && next != previous) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(next)));
      }
    });

    final conversation = state.conversation;
    return Scaffold(
      appBar: GlameaAppBar(
        titleWidget: conversation != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AppAvatar(
                    url: conversation.otherAvatarUrl(userId),
                    name: conversation.otherName(userId),
                    radius: 16,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      conversation.otherName(userId).isEmpty
                          ? 'Messages'
                          : conversation.otherName(userId),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.title
                          .copyWith(color: AppColors.textPrimary),
                    ),
                  ),
                ],
              )
            : null,
        title: conversation == null ? 'Messages' : null,
        actions: conversation != null
            ? [
                _CallButton(
                  icon: Icons.call_rounded,
                  tooltip: 'Voice call',
                  onPressed: () => _startCall(conversation, CallKind.voice),
                ),
                _CallButton(
                  icon: Icons.videocam_rounded,
                  tooltip: 'Video call',
                  onPressed: () => _startCall(conversation, CallKind.video),
                ),
              ]
            : null,
      ),
      body: Column(
        children: [
          Expanded(
            child: switch (state.status) {
              MessagesStatus.loading => const _ChatSkeleton(),
              MessagesStatus.error => ErrorState(
                  message: state.error ?? 'Could not load this conversation.',
                  onRetry: () => ref.invalidate(provider),
                ),
              MessagesStatus.ready => _MessageList(
                  messages: state.messages,
                  userId: userId,
                  otherName: state.conversation?.otherName(userId) ?? '',
                  bookingId: widget.bookingId,
                  hasMore: state.hasMore,
                  loadingMore: state.loadingMore,
                  onLoadMore: () => ref.read(provider.notifier).loadMore(),
                  onRetry: (messageId) => ref
                      .read(provider.notifier)
                      .retrySend(messageId, senderId: userId),
                ),
            },
          ),
          if (state.status == MessagesStatus.ready)
            _Composer(
              controller: _input,
              pendingImages: _pendingImages,
              showEmoji: _showEmoji,
              onToggleEmoji: () => setState(() => _showEmoji = !_showEmoji),
              onSend: _send,
              onSendLocation: _sendLocation,
              onPickImage: _pickImage,
              onRemovePendingImage: _removePendingImage,
            ),
          if (_showEmoji && state.status == MessagesStatus.ready)
            SizedBox(
              height: 280,
              child: EmojiPicker(
                textEditingController: _input,
                onEmojiSelected: (category, emoji) {
                  if (!_showEmoji) setState(() => _showEmoji = true);
                },
                onBackspacePressed: () {
                  if (_showEmoji) setState(() => _showEmoji = false);
                },
                config: Config(
                  height: 280,
                  emojiViewConfig: EmojiViewConfig(
                    columns: 8,
                    emojiSizeMax: 28,
                    backgroundColor: AppColors.white,
                  ),
                  bottomActionBarConfig: BottomActionBarConfig(
                    enabled: false,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    final userId = ref.read(authControllerProvider).user?.id ?? '';
    if (text.isEmpty && _pendingImages.isEmpty) return;
    final controller =
        ref.read(messagesControllerProvider(widget.bookingId).notifier);

    if (mounted) setState(() => _showEmoji = false);

    if (text.isNotEmpty) {
      _input.clear();
      controller.send(text, senderId: userId);
    }

    if (_pendingImages.isNotEmpty) {
      final images = List<_PendingImage>.from(_pendingImages);
      if (mounted) setState(() => _pendingImages.clear());

      for (final pending in images) {
        if (!mounted) return;
        _sendImageOptimistic(pending, userId);
      }
    }
  }

  /// Shows the picked image on the chat wall immediately (optimistic), then
  /// uploads and sends it in the background. No spinner sits on the composer.
  Future<void> _sendImageOptimistic(_PendingImage pending, String userId) async {
    final controller =
        ref.read(messagesControllerProvider(widget.bookingId).notifier);
    final localId = controller.addOptimisticImage(pending.bytes, senderId: userId);
    if (localId.isEmpty) return;
    _uploadAndSendImage(pending, localId, userId);
  }

  Future<void> _uploadAndSendImage(
      _PendingImage pending, String localId, String userId) async {
    const maxRetries = 3;
    for (var attempt = 0; attempt <= maxRetries; attempt++) {
      try {
        if (!mounted) return;
        final asset = await ref
            .read(mediaUploadControllerProvider.notifier)
            .uploadImage(pending.xFile, folder: 'glamea/messages');
        if (!mounted) return;
        await ref
            .read(messagesControllerProvider(widget.bookingId).notifier)
            .send(
          '',
          senderId: userId,
          type: MessageType.image,
          mediaUrl: (asset.secureUrl?.isNotEmpty == true)
              ? asset.secureUrl!
              : asset.publicId,
          mimeType:
              asset.format.isNotEmpty ? 'image/${asset.format}' : 'image/jpeg',
          width: asset.width,
          height: asset.height,
          localId: localId,
        );
        return;
      } catch (_) {
        if (attempt < maxRetries && mounted) {
          for (var remaining = 5; remaining > 0; remaining--) {
            if (!mounted) return;
            await Future<void>.delayed(const Duration(seconds: 1));
          }
        }
      }
    }
  }

  Future<void> _pickImage() async {
    if (_pendingImages.length >= 5) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Maximum 5 images per message.')),
        );
      }
      return;
    }
    final picker = ref.read(imagePickerProvider);
    final xFile =
        await picker.pickImage(source: ImageSource.gallery, imageQuality: 85);
    if (xFile != null && mounted) {
      final bytes = await xFile.readAsBytes();
      if (mounted) {
        setState(() => _pendingImages.add(_PendingImage(xFile: xFile, bytes: bytes)));
      }
    }
  }

  void _removePendingImage(int index) {
    setState(() => _pendingImages.removeAt(index));
  }

  Future<void> _sendLocation() async {
    final userId = ref.read(authControllerProvider).user?.id ?? '';
    if (userId.isEmpty) return;
    final result = await Navigator.of(context).push<LocationPickerResult>(
      MaterialPageRoute(builder: (_) => const LocationPickerScreen()),
    );
    if (result == null || !mounted) return;
    await ref.read(messagesControllerProvider(widget.bookingId).notifier).send(
          '',
          senderId: userId,
          type: MessageType.location,
          latitude: result.latitude,
          longitude: result.longitude,
        );
  }

  void _startCall(Conversation conversation, CallKind kind) {
    final userId = ref.read(authControllerProvider).user?.id ?? '';
    if (userId.isEmpty) return;
    final otherId = conversation.otherId(userId);
    if (otherId.isEmpty) return;
    final name = conversation.otherName(userId);
    final isVideo = kind == CallKind.video;

    showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          isVideo ? 'Video call' : 'Voice call',
          style: const TextStyle(fontWeight: FontWeight.w700),
        ),
        content: Text(
          isVideo
              ? 'Start a video call with ${name.isEmpty ? 'this person' : name}?'
              : 'Call ${name.isEmpty ? 'this person' : name}?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.primary,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded, size: 18),
                const SizedBox(width: 6),
                const Text('Call'),
              ],
            ),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true && mounted) {
        ref.read(callControllerProvider.notifier).startCall(
              bookingId: widget.bookingId,
              otherUserId: otherId,
              otherName: name,
              kind: kind,
            );
      }
    });
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon),
      color: AppColors.primary,
    );
  }
}

class _MessageList extends StatefulWidget {
  const _MessageList({
    required this.messages,
    required this.userId,
    required this.otherName,
    required this.bookingId,
    required this.hasMore,
    required this.loadingMore,
    required this.onLoadMore,
    required this.onRetry,
  });

  final List<Message> messages;
  final String userId;
  final String otherName;
  final String bookingId;
  final bool hasMore;
  final bool loadingMore;
  final VoidCallback onLoadMore;
  final void Function(String messageId) onRetry;

  @override
  State<_MessageList> createState() => _MessageListState();
}

class _MessageListState extends State<_MessageList> {
  final _scroll = ScrollController();

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Auto-loads older messages as the user scrolls to the top of the thread
  /// (Instagram DM behaviour), replacing the manual "Load earlier" button.
  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.pixels >= position.maxScrollExtent - 300) {
      widget.onLoadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.messages.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(AppSpacing.xl),
        children: const [
          SizedBox(height: 120),
          EmptyState(
            icon: Icons.forum_outlined,
            title: 'Say hello',
            message: 'Message the artist about your appointment.',
          ),
        ],
      );
    }

    final bubbles = _buildBubbles(
        widget.messages.reversed.toList(), widget.userId, widget.otherName);
    return ListView.builder(
      controller: _scroll,
      reverse: true,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
      itemCount: bubbles.length + (widget.hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (widget.hasMore && index == bubbles.length) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Center(
              child: widget.loadingMore
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: AppColors.primary),
                    )
                  : const SizedBox(height: 1),
            ),
          );
        }
        return bubbles[index];
      },
    );
  }

  List<Widget> _buildBubbles(
      List<Message> messages, String userId, String otherName) {
    final widgets = <Widget>[];
    DateTime? lastDay;
    final allImageUrls = [
      for (final m in messages)
        if ((m.type == MessageType.image || m.type == MessageType.video) &&
            m.mediaUrl.isNotEmpty)
          m.mediaUrl,
    ];
    for (final message in messages) {
      final day = message.createdAt?.toLocal();
      if (day != null && !_isSameDay(lastDay, day)) {
        widgets.add(_DateDivider(date: day));
        lastDay = day;
      }
      widgets.add(_MessageBubble(
        message: message,
        isMine: message.isMine(userId),
        otherName: otherName,
        allImageUrls: allImageUrls,
        onRetry: message.sendFailed
            ? () => widget.onRetry(message.id)
            : null,
      ));
    }
    return widgets;
  }

  bool _isSameDay(DateTime? a, DateTime b) {
    return a != null && a.year == b.year && a.month == b.month && a.day == b.day;
  }
}

class _DateDivider extends StatelessWidget {
  const _DateDivider({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.softGrey,
          borderRadius: BorderRadius.circular(AppSpacing.xs),
        ),
        child: Text(
          Formatters.date(date),
          style: AppTextStyles.caption.copyWith(color: AppColors.textMuted),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMine,
    this.otherName = '',
    this.onRetry,
    this.allImageUrls = const [],
  });

  final Message message;
  final bool isMine;
  final String otherName;
  final VoidCallback? onRetry;
  final List<String> allImageUrls;

  @override
  Widget build(BuildContext context) {
    switch (message.type) {
      case MessageType.call:
        return _CallBubble(message: message, isMine: isMine);
      case MessageType.location:
        return _LocationBubble(message: message, isMine: isMine);
      case MessageType.text:
      case MessageType.image:
      case MessageType.voice:
      case MessageType.video:
        return _buildStandardBubble(context);
    }
  }

  Widget _buildStandardBubble(BuildContext context) {
    final bubbleColor = isMine ? AppColors.primary : AppColors.white;
    final textColor = isMine ? AppColors.white : AppColors.textPrimary;
    final timeColor = isMine
        ? AppColors.white.withValues(alpha: 0.7)
        : AppColors.textMuted;

    final bool hasImage = (message.type == MessageType.image || message.type == MessageType.video) &&
        (message.mediaUrl.isNotEmpty || message.localBytes != null);

    final Widget content = Column(
      crossAxisAlignment:
          isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (hasImage)
          GestureDetector(
            onTap: () {
              if (message.localBytes != null) return;
              final urls = allImageUrls.isNotEmpty
                  ? allImageUrls
                  : [message.mediaUrl];
              final initialIndex = urls.indexOf(message.mediaUrl);
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => _FullScreenImageViewer(
                    initialIndex: initialIndex >= 0 ? initialIndex : 0,
                    urls: urls,
                  ),
                ),
              );
            },
            child: ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.xs),
              child: SizedBox(
                width: 220,
                height: 220,
                child: message.localBytes != null
                    ? Image.memory(
                        message.localBytes!,
                        fit: BoxFit.cover,
                        gaplessPlayback: true,
                      )
                    : AppImage(
                        url: message.mediaUrl,
                        fit: BoxFit.cover,
                        placeholderIcon: message.type == MessageType.video
                            ? Icons.videocam_outlined
                            : Icons.photo_outlined,
                      ),
              ),
            ),
          ),
        if (message.body.isNotEmpty && hasImage)
          const SizedBox(height: AppSpacing.xs),
        if (message.body.isNotEmpty)
          Text(
            message.body,
            style: AppTextStyles.bodyMedium.copyWith(color: textColor),
          ),
        if (!hasImage && message.body.isEmpty && message.type == MessageType.image)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.photo_outlined, size: 16, color: textColor),
              const SizedBox(width: 4),
              Text(
                'Photo',
                style: AppTextStyles.bodyMedium.copyWith(color: textColor),
              ),
            ],
          ),
        if (!hasImage && message.body.isEmpty && message.type == MessageType.video)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.videocam_outlined, size: 16, color: textColor),
              const SizedBox(width: 4),
              Text(
                'Video',
                style: AppTextStyles.bodyMedium.copyWith(color: textColor),
              ),
            ],
          ),
        if (message.createdAt != null) ...[
          const SizedBox(height: 2),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                Formatters.time(message.createdAt!),
                style: AppTextStyles.caption
                    .copyWith(color: timeColor, fontSize: 11),
              ),
              if (isMine) ...[
                const SizedBox(width: 3),
                if (message.pending)
                  const SizedBox(
                    width: 11,
                    height: 11,
                    child: CircularProgressIndicator(
                      strokeWidth: 1.5,
                      color: Colors.white70,
                    ),
                  )
                else
                  Icon(
                    message.isRead
                        ? Icons.done_all_rounded
                        : Icons.done_rounded,
                    size: 13,
                    color: message.isRead
                        ? AppColors.white.withValues(alpha: 0.85)
                        : timeColor,
                  ),
              ],
            ],
          ),
        ],
      ],
    );

    final bubble = Container(
      constraints: BoxConstraints(
        maxWidth: MediaQuery.of(context).size.width * 0.7,
      ),
      padding:
          const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: hasImage ? Colors.transparent : bubbleColor,
        borderRadius: BorderRadius.only(
          topLeft: Radius.circular(isMine ? AppSpacing.md : AppSpacing.xs),
          topRight: Radius.circular(isMine ? AppSpacing.xs : AppSpacing.md),
          bottomLeft: const Radius.circular(AppSpacing.md),
          bottomRight: const Radius.circular(AppSpacing.md),
        ),
        border: isMine ? null : Border.all(color: AppColors.borderSubtle),
      ),
      child: content,
    );

    final visibleBubble = Opacity(
      opacity: isMine && message.pending ? 0.6 : 1,
      child: bubble,
    );

    final failedIndicator = message.sendFailed
        ? GestureDetector(
            onTap: onRetry,
            child: Container(
              margin: const EdgeInsets.only(top: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: AppColors.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, color: AppColors.error, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    'Failed. Tap to retry',
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.error,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
          )
        : const SizedBox.shrink();

    if (isMine) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
        child: Align(
          alignment: Alignment.centerRight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [visibleBubble, failedIndicator],
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          AppAvatar(name: otherName, radius: 15),
          const SizedBox(width: AppSpacing.xs),
          Flexible(child: visibleBubble),
        ],
      ),
    );
  }
}

/// Centered system-style card for a call record (missed/declined/answered +
/// duration).
class _CallBubble extends StatelessWidget {
  const _CallBubble({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final status = message.callStatus ?? CallStatus.answered;
    final isVideo = message.callType == CallKind.video;
    final missed = status == CallStatus.missed;
    final declined = status == CallStatus.declined;
    final notConnected = missed || declined;

    final IconData icon;
    if (isVideo) {
      icon = notConnected ? Icons.videocam_off_rounded : Icons.videocam_rounded;
    } else if (missed) {
      icon = Icons.call_missed_rounded;
    } else if (declined) {
      icon = Icons.phone_disabled_rounded;
    } else {
      icon = Icons.call_rounded;
    }

    final String label;
    if (isVideo) {
      label = missed
          ? 'Missed video call'
          : (declined ? 'Declined video call' : 'Video call');
    } else {
      label = missed
          ? 'Missed call'
          : (declined ? 'Declined call' : 'Call');
    }

    final color = notConnected
        ? AppColors.error
        : (isMine ? AppColors.primary : AppColors.textPrimary);

    final durationMs = message.durationMs ?? 0;
    final durationText = durationMs > 0 ? _formatDuration(durationMs) : null;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.xs,
            ),
            decoration: BoxDecoration(
              color: notConnected
                  ? AppColors.error.withValues(alpha: 0.08)
                  : AppColors.softGrey,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(width: AppSpacing.xs),
                Flexible(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: AppTextStyles.bodyMedium.copyWith(
                          color: color,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      if (durationText != null)
                        Text(
                          durationText,
                          style: AppTextStyles.caption
                              .copyWith(color: AppColors.textMuted),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDuration(int ms) {
    final seconds = (ms / 1000).round();
    final minutes = seconds ~/ 60;
    final remainder = seconds % 60;
    return '$minutes:${remainder.toString().padLeft(2, '0')}';
  }
}

/// Location card: a non-interactive map preview with a pin plus an address
/// line. Tapping opens the full-screen [LocationMapScreen].
class _LocationBubble extends StatelessWidget {
  const _LocationBubble({required this.message, required this.isMine});

  final Message message;
  final bool isMine;

  @override
  Widget build(BuildContext context) {
    final lat = message.latitude;
    final lng = message.longitude;
    if (lat == null || lng == null) return const SizedBox.shrink();
    final point = LatLng(lat, lng);
    final address = message.address;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
      child: Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: GestureDetector(
          onTap: () {
            HapticFeedback.selectionClick();
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => LocationMapScreen(
                  args: LocationMapArgs(
                    latitude: lat,
                    longitude: lng,
                    title: address.isEmpty ? 'Shared location' : null,
                    subtitle: address.isEmpty ? null : address,
                  ),
                ),
              ),
            );
          },
          child: Container(
            width: MediaQuery.of(context).size.width * 0.62,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.white,
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(isMine ? AppSpacing.md : AppSpacing.xs),
                topRight: Radius.circular(isMine ? AppSpacing.xs : AppSpacing.md),
                bottomLeft: const Radius.circular(AppSpacing.md),
                bottomRight: const Radius.circular(AppSpacing.md),
              ),
              border: Border.all(color: AppColors.borderSubtle),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  height: 130,
                  child: FlutterMap(
                    options: MapOptions(
                      initialCenter: point,
                      initialZoom: 14,
                      interactionOptions: const InteractionOptions(
                        flags: InteractiveFlag.none,
                      ),
                    ),
                    children: [
                      TileLayer(
                        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                        userAgentPackageName: 'com.glamea.glamea',
                      ),
                      MarkerLayer(
                        markers: [
                          Marker(
                            point: point,
                            width: 36,
                            height: 36,
                            child: const Icon(
                              Icons.location_pin,
                              color: AppColors.primary,
                              size: 36,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.location_on_outlined,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      const SizedBox(width: AppSpacing.xs),
                      Expanded(
                        child: Text(
                          address.isEmpty ? 'Shared location' : address,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.bodyMedium.copyWith(
                            color: AppColors.textPrimary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.pendingImages,
    required this.showEmoji,
    required this.onToggleEmoji,
    required this.onSend,
    required this.onSendLocation,
    required this.onPickImage,
    required this.onRemovePendingImage,
  });

  final TextEditingController controller;
  final List<_PendingImage> pendingImages;
  final bool showEmoji;
  final VoidCallback onToggleEmoji;
  final VoidCallback onSend;
  final VoidCallback onSendLocation;
  final VoidCallback onPickImage;
  final void Function(int index) onRemovePendingImage;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(
            AppSpacing.md, AppSpacing.sm, AppSpacing.sm, AppSpacing.sm),
        decoration: const BoxDecoration(
          color: AppColors.white,
          border: Border(top: BorderSide(color: AppColors.borderSubtle)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Pending image thumbnails
            if (pendingImages.isNotEmpty) ...[
              SizedBox(
                height: 80,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: pendingImages.length,
                  separatorBuilder: (_, __) =>
                      const SizedBox(width: AppSpacing.xs),
                  itemBuilder: (context, index) {
                    return Stack(
                      clipBehavior: Clip.none,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: SizedBox(
                            width: 72,
                            height: 72,
                            child: Image.memory(
                              pendingImages[index].bytes,
                              fit: BoxFit.cover,
                              gaplessPlayback: true,
                              errorBuilder: (_, __, ___) => Container(
                                color: AppColors.softGrey,
                                child: const Icon(Icons.photo_outlined,
                                    color: AppColors.textMuted),
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: -4,
                          right: -4,
                          child: GestureDetector(
                            onTap: () => onRemovePendingImage(index),
                            child: Container(
                              padding: const EdgeInsets.all(2),
                              decoration: const BoxDecoration(
                                color: AppColors.error,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(Icons.close,
                                  size: 14, color: AppColors.white),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                SizedBox(
                  height: 44,
                  child: IconButton(
                    onPressed: onToggleEmoji,
                    tooltip: 'Emoji',
                    icon: Icon(
                      showEmoji ? Icons.keyboard : Icons.emoji_emotions_outlined,
                      color: showEmoji ? AppColors.primary : AppColors.roseGold,
                    ),
                  ),
                ),
                Expanded(
                  child: TextField(
                    controller: controller,
                    minLines: 1,
                    maxLines: 4,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: InputDecoration(
                      hintText: pendingImages.isNotEmpty
                          ? 'Add a caption…'
                          : 'Write a message…',
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  height: 44,
                  child: IconButton(
                    onPressed: onPickImage,
                    tooltip: 'Add image',
                    icon: Icon(
                      Icons.photo_camera_outlined,
                      color: pendingImages.isNotEmpty
                          ? AppColors.primary
                          : AppColors.roseGold,
                    ),
                  ),
                ),
                SizedBox(
                  height: 44,
                  child: IconButton(
                    onPressed: onSendLocation,
                    tooltip: 'Share location',
                    icon: const Icon(
                      Icons.location_on_outlined,
                      color: AppColors.primary,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                SizedBox(
                  height: 44,
                  child: IconButton.filled(
                    onPressed: onSend,
                    style: IconButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: AppColors.white,
                    ),
                    icon: const Icon(Icons.send_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _FullScreenImageViewer extends StatelessWidget {
  const _FullScreenImageViewer({
    required this.initialIndex,
    required this.urls,
  });

  final int initialIndex;
  final List<String> urls;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: PageView.builder(
        itemCount: urls.length,
        controller: PageController(
          initialPage: initialIndex,
        ),
        itemBuilder: (context, index) {
          return InteractiveViewer(
            minScale: 0.5,
            maxScale: 4.0,
            child: Center(
              child: Image.network(
                urls[index],
                fit: BoxFit.contain,
                loadingBuilder: (context, child, loadingProgress) {
                  if (loadingProgress == null) return child;
                  return const Center(
                    child: CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2,
                    ),
                  );
                },
                errorBuilder: (context, error, stackTrace) {
                  return const Center(
                    child: Icon(
                      Icons.broken_image_outlined,
                      color: Colors.white54,
                      size: 48,
                    ),
                  );
                },
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ChatSkeleton extends StatelessWidget {
  const _ChatSkeleton();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: AppSpacing.md),
      child: SkeletonChatBubbles(count: 6),
    );
  }
}

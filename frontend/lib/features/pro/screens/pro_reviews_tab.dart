import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/app_colors.dart';
import '../../../app/theme/app_spacing.dart';
import '../../../app/theme/app_typography.dart';
import '../../../core/utils/formatters.dart';
import '../../../models/review.dart';
import '../../../shared/widgets/app_card.dart';
import '../../../shared/widgets/app_image.dart';
import '../../../shared/widgets/app_states.dart';
import '../pro_controller.dart';

/// Professional reviews: read feedback and respond.
class ProReviewsTab extends ConsumerWidget {
  const ProReviewsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(proReviewsControllerProvider);

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.md, AppSpacing.sm),
            child: Text('Reviews', style: AppTextStyles.headline2),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.read(proReviewsControllerProvider.notifier).refresh(),
              color: AppColors.primary,
              child: _buildList(context, ref, state),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, ProListState<Review> state) {
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
            message: state.error ?? 'Could not load reviews.',
            onRetry: () => ref.read(proReviewsControllerProvider.notifier).refresh(),
          ),
        ],
      );
    }
    if (state.items.isEmpty) {
      return ListView(
        children: const [
          EmptyState(
            icon: Icons.star_outline_rounded,
            title: 'No reviews yet',
            message: 'Customer reviews will appear here after bookings are completed.',
          ),
        ],
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, 0, AppSpacing.md, AppSpacing.lg),
      itemCount: state.items.length,
      separatorBuilder: (_, __) => const SizedBox(height: AppSpacing.sm),
      itemBuilder: (_, i) => _ReviewCard(
        review: state.items[i],
        onRespond: (response) => ref.read(proReviewsControllerProvider.notifier).respond(state.items[i].id, response),
      ),
    );
  }
}

class _ReviewCard extends ConsumerStatefulWidget {
  const _ReviewCard({required this.review, required this.onRespond});
  final Review review;
  final Future<void> Function(String response) onRespond;

  @override
  ConsumerState<_ReviewCard> createState() => _ReviewCardState();
}

class _ReviewCardState extends ConsumerState<_ReviewCard> {
  bool _replying = false;
  bool _sending = false;
  final _reply = TextEditingController();

  @override
  void dispose() {
    _reply.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_reply.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await widget.onRespond(_reply.text.trim());
      if (!mounted) return;
      _reply.clear();
      setState(() {
        _replying = false;
        _sending = false;
      });
      messenger.showSnackBar(const SnackBar(content: Text('Response posted')));
    } catch (e) {
      if (!mounted) return;
      messenger.showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
      setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.review;
    final responded = r.response != null && r.response!.isNotEmpty;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              AppAvatar(name: r.customerName, radius: 18),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Text(r.customerName.isEmpty ? 'Customer' : r.customerName, maxLines: 1, overflow: TextOverflow.ellipsis, style: AppTextStyles.bodyMedium.copyWith(fontWeight: FontWeight.w700)),
                Text(Formatters.relativeTime(r.createdAt ?? DateTime.now()), style: AppTextStyles.caption.copyWith(color: AppColors.textSecondary)),
                  ],
                ),
              ),
              RatingStars(rating: r.rating.toDouble(), size: 16, showValue: true),
            ],
          ),
          if (r.comment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.sm),
            Text(r.comment, style: AppTextStyles.bodyMedium),
          ],
          if (responded) ...[
            const SizedBox(height: AppSpacing.sm),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.softGrey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your response', style: AppTextStyles.caption.copyWith(color: AppColors.primary, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(r.response!, style: AppTextStyles.bodyMedium),
                ],
              ),
            ),
          ],
          if (!responded) ...[
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () => setState(() => _replying = !_replying),
                child: Text(_replying ? 'Cancel' : 'Respond'),
              ),
            ),
            if (_replying)
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  TextField(
                    controller: _reply,
                    maxLines: 3,
                    decoration: const InputDecoration(hintText: 'Thank them for their feedback...', alignLabelWithHint: true),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  FilledButton(
                    onPressed: _sending ? null : _send,
                    style: FilledButton.styleFrom(backgroundColor: AppColors.primary),
                    child: _sending
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                        : const Text('Post response'),
                  ),
                ],
              ),
          ],
        ],
      ),
    );
  }
}

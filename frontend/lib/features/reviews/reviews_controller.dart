import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/review.dart';
import 'data/review_api.dart';

enum MyReviewsStatus { loading, ready, error }

class MyReviewsState {
  const MyReviewsState({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.error,
  });

  final MyReviewsStatus status;
  final List<Review> items;
  final int total;
  final String? error;
}

/// Reviews written by the current customer (GET /reviews/me).
class MyReviewsController extends Notifier<MyReviewsState> {
  @override
  MyReviewsState build() {
    _load();
    return const MyReviewsState(status: MyReviewsStatus.loading);
  }

  Future<void> _load() async {
    try {
      final result = await ref.read(reviewApiProvider).fetchMyReviews();
      state = MyReviewsState(
        status: MyReviewsStatus.ready,
        items: result.items,
        total: result.total,
      );
    } on AppException catch (e) {
      state = MyReviewsState(status: MyReviewsStatus.error, error: e.message);
    } catch (_) {
      state = const MyReviewsState(
        status: MyReviewsStatus.error,
        error: 'Could not load your reviews. Please try again.',
      );
    }
  }

  Future<void> refresh() => _load();
}

final myReviewsControllerProvider =
    NotifierProvider<MyReviewsController, MyReviewsState>(MyReviewsController.new);

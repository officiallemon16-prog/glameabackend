import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/errors/app_exception.dart';
import '../../models/dispute.dart';
import 'data/dispute_api.dart';

// ---------------------------------------------------------------------------
// Dispute list
// ---------------------------------------------------------------------------

enum MyDisputesStatus { loading, ready, error }

class MyDisputesState {
  const MyDisputesState({
    required this.status,
    this.items = const [],
    this.total = 0,
    this.error,
  });

  final MyDisputesStatus status;
  final List<Dispute> items;
  final int total;
  final String? error;
}

/// Disputes the current user is part of (GET /disputes/me).
class MyDisputesController extends Notifier<MyDisputesState> {
  @override
  MyDisputesState build() {
    _load();
    return const MyDisputesState(status: MyDisputesStatus.loading);
  }

  Future<void> _load() async {
    try {
      final result = await ref.read(disputeApiProvider).fetchMyDisputes();
      state = MyDisputesState(
        status: MyDisputesStatus.ready,
        items: result.items,
        total: result.total,
      );
    } on AppException catch (e) {
      state = MyDisputesState(status: MyDisputesStatus.error, error: e.message);
    } catch (_) {
      state = const MyDisputesState(
        status: MyDisputesStatus.error,
        error: 'Could not load disputes. Please try again.',
      );
    }
  }

  Future<void> refresh() => _load();
}

final myDisputesControllerProvider =
    NotifierProvider<MyDisputesController, MyDisputesState>(MyDisputesController.new);

// ---------------------------------------------------------------------------
// Dispute detail (thread)
// ---------------------------------------------------------------------------

enum DisputeDetailStatus { loading, ready, error }

class DisputeDetailState {
  const DisputeDetailState({
    required this.status,
    this.dispute,
    this.messages = const [],
    this.error,
    this.sending = false,
    this.sendError,
  });

  final DisputeDetailStatus status;
  final Dispute? dispute;
  final List<DisputeMessage> messages;
  final String? error;
  final bool sending;
  final String? sendError;

  DisputeDetailState copyWith({
    DisputeDetailStatus? status,
    Dispute? dispute,
    List<DisputeMessage>? messages,
    String? error,
    bool? sending,
    String? sendError,
  }) {
    return DisputeDetailState(
      status: status ?? this.status,
      dispute: dispute ?? this.dispute,
      messages: messages ?? this.messages,
      error: error ?? this.error,
      sending: sending ?? this.sending,
      sendError: sendError ?? this.sendError,
    );
  }
}

/// Loads a dispute and its message thread; supports replying while open.
class DisputeDetailController extends FamilyNotifier<DisputeDetailState, String> {
  @override
  DisputeDetailState build(String disputeId) {
    _load(disputeId);
    return const DisputeDetailState(status: DisputeDetailStatus.loading);
  }

  Future<void> _load(String disputeId) async {
    try {
      final api = ref.read(disputeApiProvider);
      final dispute = await api.fetchDispute(disputeId);
      final messages = await api.fetchMessages(disputeId);
      state = DisputeDetailState(
        status: DisputeDetailStatus.ready,
        dispute: dispute,
        messages: messages,
      );
    } on AppException catch (e) {
      state = DisputeDetailState(status: DisputeDetailStatus.error, error: e.message);
    } catch (_) {
      state = const DisputeDetailState(
        status: DisputeDetailStatus.error,
        error: 'Could not load this dispute. Please try again.',
      );
    }
  }

  Future<void> refresh() {
    final id = arg;
    return _load(id);
  }

  /// Adds a message; returns true on success (so callers clear input).
  Future<bool> addMessage(String body) async {
    final text = body.trim();
    final dispute = state.dispute;
    if (text.isEmpty || state.sending || dispute == null || !dispute.isOpen) return false;

    state = state.copyWith(sending: true, sendError: null);
    try {
      final message = await ref.read(disputeApiProvider).addMessage(arg, text);
      state = state.copyWith(
        sending: false,
        messages: [...state.messages, message],
      );
      return true;
    } on AppException catch (e) {
      state = state.copyWith(sending: false, sendError: e.message);
      return false;
    } catch (_) {
      state = state.copyWith(
        sending: false,
        sendError: 'Could not send your message. Please try again.',
      );
      return false;
    }
  }
}

final disputeDetailControllerProvider =
    NotifierProvider.family<DisputeDetailController, DisputeDetailState, String>(
  DisputeDetailController.new,
);

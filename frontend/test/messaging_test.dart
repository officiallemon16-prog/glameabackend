import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:glamea/features/messaging/data/messaging_api.dart';
import 'package:glamea/features/messaging/messaging_controller.dart';
import 'package:glamea/models/conversation.dart';
import 'package:glamea/models/message.dart';

final conversation = Conversation(
  id: 'c-1',
  bookingId: 'b-1',
  customerId: 'cust-1',
  professionalId: 'pro-1',
  professionalUserId: 'pro-user-1',
  lastMessage: 'Sounds good',
  lastMessageAt: DateTime.utc(2026, 8, 14, 9),
  professionalName: "Ada's Beauty Studio",
  customerName: 'Amina Bello',
  serviceName: 'Sweep',
);

const messageFromProfessional = Message(
  id: 'm-1',
  conversationId: 'c-1',
  senderId: 'pro-1',
  recipientId: 'cust-1',
  body: 'Looking forward to it',
  isRead: false,
);

const messageFromCustomer = Message(
  id: 'm-2',
  conversationId: 'c-1',
  senderId: 'cust-1',
  recipientId: 'pro-1',
  body: 'See you then',
  isRead: true,
);

class FakeMessagingApi extends MessagingApi {
  FakeMessagingApi() : super(Dio());

  final List<String> readBookings = [];
  String? lastSentBody;

  @override
  Future<List<Conversation>> fetchConversations({int limit = 50, int offset = 0}) async {
    return [conversation];
  }

  @override
  Future<Conversation> fetchConversation(String bookingId) async => conversation;

  @override
  Future<List<Message>> fetchMessages(
    String bookingId, {
    int limit = 50,
    int offset = 0,
    DateTime? before,
    String? beforeId,
  }) async {
    return [messageFromProfessional, messageFromCustomer];
  }

  @override
  Future<Message> sendMessage(
    String bookingId, {
    String body = '',
    String type = 'text',
    String? mediaAssetId,
    String? mediaUrl,
    String? mimeType,
    int? durationMs,
    int? width,
    int? height,
    double? latitude,
    double? longitude,
    String? address,
    String? callType,
    String? callStatus,
  }) async {
    lastSentBody = body;
    return Message(
      id: 'm-3',
      conversationId: conversation.id,
      senderId: 'cust-1',
      recipientId: 'pro-1',
      body: body,
      createdAt: DateTime.utc(2026, 8, 14, 9, 30),
    );
  }

  @override
  Future<void> markRead(String bookingId) async {
    readBookings.add(bookingId);
  }
}

void main() {
  group('Conversation', () {
    test('parses payload', () {
      final value = Conversation.fromJson(const {
        'id': 'c-1',
        'booking_id': 'b-1',
        'customer_id': 'cust-1',
        'professional_id': 'pro-1',
        'last_message': 'Sounds good',
        'last_message_at': '2026-08-14T09:00:00Z',
        'professional_name': "Ada's Beauty Studio",
        'customer_name': 'Amina Bello',
        'service_name': 'Sweep',
      });

      expect(value.id, 'c-1');
      expect(value.bookingId, 'b-1');
      expect(value.lastMessage, 'Sounds good');
      expect(value.lastMessageAt, isNotNull);
      expect(value.serviceName, 'Sweep');
    });

    test('otherName returns the counterpart for the viewer', () {
      expect(conversation.otherName('cust-1'), "Ada's Beauty Studio");
      expect(conversation.otherName('pro-user-1'), 'Amina Bello');
    });
  });

  group('Message', () {
    test('parses payload and derives isMine', () {
      final message = Message.fromJson(const {
        'id': 'm-1',
        'conversation_id': 'c-1',
        'sender_id': 'pro-1',
        'recipient_id': 'cust-1',
        'body': 'Hello',
        'is_read': false,
        'created_at': '2026-08-14T09:00:00Z',
      });

      expect(message.conversationId, 'c-1');
      expect(message.body, 'Hello');
      expect(message.isRead, isFalse);
      expect(message.isMine('pro-1'), isTrue);
      expect(message.isMine('cust-1'), isFalse);
    });

    test('missing fields fall back safely', () {
      final message = Message.fromJson(const {'id': 'm-9'});

      expect(message.body, isEmpty);
      expect(message.isRead, isFalse);
      expect(message.createdAt, isNull);
    });
  });

  group('ConversationsController', () {
    test('loads conversations into ready state', () async {
      final container = ProviderContainer(
        overrides: [messagingApiProvider.overrideWithValue(FakeMessagingApi())],
      );
      addTearDown(container.dispose);

      expect(
        container.read(conversationsControllerProvider).status,
        ConversationsStatus.loading,
      );
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(conversationsControllerProvider);
      expect(state.status, ConversationsStatus.ready);
      expect(state.conversations, hasLength(1));
      expect(state.conversations.first.bookingId, 'b-1');
    });

    test('refresh keeps the list fresh', () async {
      final container = ProviderContainer(
        overrides: [messagingApiProvider.overrideWithValue(FakeMessagingApi())],
      );
      addTearDown(container.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      await container.read(conversationsControllerProvider.notifier).refresh();

      expect(container.read(conversationsControllerProvider).conversations, hasLength(1));
    });
  });

  group('MessagesController', () {
    test('loads conversation and messages and marks them read', () async {
      final api = FakeMessagingApi();
      final container = ProviderContainer(
        overrides: [messagingApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      expect(container.read(messagesControllerProvider('b-1')).status, MessagesStatus.loading);
      await Future<void>.delayed(const Duration(milliseconds: 20));

      final state = container.read(messagesControllerProvider('b-1'));
      expect(state.status, MessagesStatus.ready);
      expect(state.conversation?.bookingId, 'b-1');
      expect(state.messages, hasLength(2));
      expect(api.readBookings, contains('b-1'));
    });

    test('send appends the new message and clears the error', () async {
      final api = FakeMessagingApi();
      final container = ProviderContainer(
        overrides: [messagingApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(messagesControllerProvider('b-1').notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final sent = await notifier.send('See you at 10', senderId: 'cust-1');

      expect(sent, isTrue);
      expect(api.lastSentBody, 'See you at 10');
      final state = container.read(messagesControllerProvider('b-1'));
      expect(state.messages, hasLength(3));
      expect(state.messages.last.body, 'See you at 10');
      expect(state.sendError, isNull);
    });

    test('empty or whitespace messages are not sent', () async {
      final api = FakeMessagingApi();
      final container = ProviderContainer(
        overrides: [messagingApiProvider.overrideWithValue(api)],
      );
      addTearDown(container.dispose);

      final notifier = container.read(messagesControllerProvider('b-1').notifier);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(await notifier.send('   ', senderId: 'cust-1'), isFalse);
      expect(api.lastSentBody, isNull);
      expect(container.read(messagesControllerProvider('b-1')).messages, hasLength(2));
    });
  });
}

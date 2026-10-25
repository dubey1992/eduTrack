import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/communication/data/models/message.dart';
import 'package:edutrack_app/features/my_inbox/data/my_inbox_repository.dart';

/// The person's inbox, in memory. Marking read moves a message along the
/// way the server does.
class FakeMyInboxRepository implements MyInboxRepository {
  FakeMyInboxRepository({List<Message>? messages, this.failListWith}) : messages = messages ?? [];

  List<Message> messages;
  Failure? failListWith;
  bool? lastUnreadOnly;
  final List<int> markedRead = [];

  @override
  Future<PaginatedResponse<Message>> inbox({required bool unreadOnly, required int page, required int perPage}) async {
    lastUnreadOnly = unreadOnly;
    if (failListWith != null) throw failListWith!;
    final items = unreadOnly ? messages.where((m) => m.isUnread).toList() : messages;
    return PaginatedResponse(items: items, currentPage: 1, lastPage: 1, total: items.length, perPage: perPage);
  }

  @override
  Future<int> unreadCount() async => messages.where((m) => m.isUnread).length;

  @override
  Future<Message> markRead(int messageId) async {
    markedRead.add(messageId);
    messages = [
      for (final m in messages) m.id == messageId ? inboxMessage(id: m.id, subject: m.subject, read: true) : m,
    ];
    return messages.firstWhere((m) => m.id == messageId);
  }

  @override
  Future<int> markAllRead() async {
    final count = messages.where((m) => m.isUnread).length;
    messages = [for (final m in messages) inboxMessage(id: m.id, subject: m.subject, read: true)];
    return count;
  }
}

Message inboxMessage({
  int id = 1,
  String? subject = 'Sports day on Friday',
  String body = 'Sports day is on Friday 30 October. Classes end at noon.',
  bool read = false,
  MessageCategory category = MessageCategory.announcement,
  String? studentName,
}) {
  return Message(
    id: id,
    schoolId: 1,
    event: 'announcement',
    eventLabel: 'Announcement',
    category: category,
    channel: MessageChannel.inApp,
    recipientName: 'Meera Joshi',
    recipientMobile: null,
    studentId: null,
    studentName: studentName,
    subject: subject,
    body: body,
    status: MessageStatus.sent,
    provider: null,
    providerLabel: null,
    failureReason: null,
    sentAt: '2026-10-26T04:00:00Z',
    readAt: read ? '2026-10-26T05:00:00Z' : null,
    createdAt: '2026-10-26T04:00:00Z',
    createdAtLabel: '9:30 AM',
    createdOnLabel: '10/26/2026',
    sentAtLabel: '9:30 AM',
  );
}

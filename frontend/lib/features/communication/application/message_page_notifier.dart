import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/communication_repository.dart';
import '../data/models/message.dart';
import 'inbox_notifier.dart';

final messagePageNotifierProvider = AsyncNotifierProvider<MessagePageNotifier, PagedList<Message>>(
  MessagePageNotifier.new,
);

/// The paginated message log behind the Communication Center, with the
/// prototype's category tabs plus status, channel, date and search filters.
class MessagePageNotifier extends AsyncNotifier<PagedList<Message>> {
  int? _schoolId;
  MessageCategory? _category;
  MessageChannel? _channel;
  MessageStatus? _status;
  String? _dateFrom;
  String? _dateTo;
  String? _search;
  int _page = 1;
  int _perPage = 20;

  MessageCategory? get category => _category;

  @override
  Future<PagedList<Message>> build() => _fetch();

  Future<PagedList<Message>> _fetch() async {
    final response = await ref
        .read(communicationRepositoryProvider)
        .listMessages(
          schoolId: _schoolId,
          category: _category,
          channel: _channel,
          status: _status,
          dateFrom: _dateFrom,
          dateTo: _dateTo,
          search: _search,
          page: _page,
          perPage: _perPage,
        );

    return PagedList(
      items: response.items,
      currentPage: response.currentPage,
      lastPage: response.lastPage,
      total: response.total,
      perPage: response.perPage,
    );
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setSchoolFilter(int? schoolId) async {
    _schoolId = schoolId;
    _page = 1;
    await refresh();
  }

  Future<void> setCategory(MessageCategory? category) async {
    _category = category;
    _page = 1;
    await refresh();
  }

  Future<void> setFilters({
    MessageChannel? channel,
    MessageStatus? status,
    String? dateFrom,
    String? dateTo,
    String? search,
  }) async {
    _channel = channel;
    _status = status;
    _dateFrom = dateFrom;
    _dateTo = dateTo;
    _search = (search ?? '').trim().isEmpty ? null : search!.trim();
    _page = 1;
    await refresh();
  }

  Future<void> goToPage(int page) async {
    _page = page;
    await refresh();
  }

  Future<void> setPerPage(int perPage) async {
    _perPage = perPage;
    _page = 1;
    await refresh();
  }

  /// Puts a failed message back on the queue and refreshes the KPI tiles
  /// alongside the list, since both change.
  Future<void> retry(Message message) async {
    await ref.read(communicationRepositoryProvider).retry(message.id);
    ref.invalidate(messageSummaryProvider);
    await refresh();
  }

  /// A message written by hand. One person is sent at once and lands in the
  /// log immediately; a group is queued, so the log fills in as the worker
  /// gets through it. Either way the list and the tiles are re-read.
  Future<NoticeResult> sendNotice({
    int? schoolId,
    required NoticeKind kind,
    required NoticeAudience audienceType,
    int? audienceId,
    NoticeRecipients? recipients,
    required List<MessageChannel> channels,
    String? subject,
    String? body,
    String? amount,
    String? dueDate,
  }) async {
    final result = await ref
        .read(communicationRepositoryProvider)
        .sendNotice(
          schoolId: schoolId,
          kind: kind,
          audienceType: audienceType,
          audienceId: audienceId,
          recipients: recipients,
          channels: channels,
          subject: subject,
          body: body,
          amount: amount,
          dueDate: dueDate,
        );

    ref.invalidate(messageSummaryProvider);
    // A staff audience includes the sender's own inbox.
    ref.invalidate(inboxNotifierProvider);
    ref.invalidate(unreadCountProvider);
    _page = 1;
    await refresh();

    return result;
  }
}

/// The four KPI tiles. Kept separate from the list so paging does not
/// re-count the day's traffic.
final messageSummaryProvider = FutureProvider.autoDispose.family<MessageSummary, int?>((ref, schoolId) {
  return ref.watch(communicationRepositoryProvider).summary(schoolId: schoolId);
});

/// How many people a notice would reach, per channel, as the compose form
/// changes. No automatic retry: a refused audience is an answer, not a blip.
final noticePreviewProvider = FutureProvider.autoDispose.family<NoticeResult, NoticeQuery>((ref, query) {
  return ref
      .watch(communicationRepositoryProvider)
      .previewNotice(
        schoolId: query.schoolId,
        kind: query.kind,
        audienceType: query.audienceType,
        audienceId: query.audienceId,
        recipients: query.recipients,
        channels: query.channels,
      );
}, retry: (retryCount, error) => null);

/// The compose form's current choices, as a provider key.
class NoticeQuery {
  const NoticeQuery({
    required this.kind,
    required this.audienceType,
    required this.channels,
    this.schoolId,
    this.audienceId,
    this.recipients,
  });

  final NoticeKind kind;
  final NoticeAudience audienceType;
  final List<MessageChannel> channels;
  final int? schoolId;
  final int? audienceId;
  final NoticeRecipients? recipients;

  @override
  bool operator ==(Object other) =>
      other is NoticeQuery &&
      other.kind == kind &&
      other.audienceType == audienceType &&
      MessageChannel.joined(other.channels) == MessageChannel.joined(channels) &&
      other.schoolId == schoolId &&
      other.audienceId == audienceId &&
      other.recipients == recipients;

  @override
  int get hashCode =>
      Object.hash(kind, audienceType, MessageChannel.joined(channels), schoolId, audienceId, recipients);
}

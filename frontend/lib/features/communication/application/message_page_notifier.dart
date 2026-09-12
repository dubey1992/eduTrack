import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/communication_repository.dart';
import '../data/models/message.dart';

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
}

/// The four KPI tiles. Kept separate from the list so paging does not
/// re-count the day's traffic.
final messageSummaryProvider = FutureProvider.autoDispose.family<MessageSummary, int?>((ref, schoolId) {
  return ref.watch(communicationRepositoryProvider).summary(schoolId: schoolId);
});

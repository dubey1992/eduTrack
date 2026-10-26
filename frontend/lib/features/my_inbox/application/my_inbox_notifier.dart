import '../../../core/utils/date_period.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../communication/data/models/message.dart';
import '../data/my_inbox_repository.dart';

/// The badge on the bell. Re-read whenever a screen with the bell is built,
/// and after anything is marked read; a failure shows no badge rather than a
/// wrong number.
final myUnreadCountProvider = FutureProvider.autoDispose<int>(
  (ref) => ref.read(myInboxRepositoryProvider).unreadCount(),
  retry: (retryCount, error) => null,
);

class MyInbox {
  const MyInbox({
    required this.items,
    required this.hasMore,
    required this.page,
    required this.unreadOnly,
    this.period = DatePeriod.all,
  });

  final List<Message> items;
  final bool hasMore;
  final int page;
  final bool unreadOnly;

  /// The period the inbox is filtered to.
  final DatePeriod period;

  MyInbox copyWith({List<Message>? items}) =>
      MyInbox(items: items ?? this.items, hasMore: hasMore, page: page, unreadOnly: unreadOnly, period: period);
}

final myInboxProvider = AsyncNotifierProvider.autoDispose<MyInboxNotifier, MyInbox>(
  MyInboxNotifier.new,
  retry: (retryCount, error) => null,
);

/// The School365ai app's inbox (docs/teacher-app.md, T4): what the school
/// sent this person in the app - announcements, leave decisions, alerts -
/// newest first. Pull-only until push notifications arrive (T6).
class MyInboxNotifier extends AsyncNotifier<MyInbox> {
  static const perPage = 20;

  bool _unreadOnly = false;
  DatePeriod _period = DatePeriod.all;

  /// The chosen period - read by the chips, which show it while loading too.
  DatePeriod get period => _period;

  @override
  Future<MyInbox> build() => _page(1, const []);

  Future<MyInbox> _page(int page, List<Message> before) async {
    final range = _period.rangeFrom(DateTime.now());
    final response = await ref
        .read(myInboxRepositoryProvider)
        .inbox(unreadOnly: _unreadOnly, dateFrom: range?.from, dateTo: range?.to, page: page, perPage: perPage);

    return MyInbox(
      items: [...before, ...response.items],
      hasMore: response.currentPage < response.lastPage,
      page: response.currentPage,
      unreadOnly: _unreadOnly,
      period: _period,
    );
  }

  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
    ref.invalidate(myUnreadCountProvider);
  }

  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Day / week / month (docs/teacher-app.md, "Filters by period").
  Future<void> setPeriod(DatePeriod period) async {
    _period = period;
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> setUnreadOnly(bool unreadOnly) async {
    _unreadOnly = unreadOnly;
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore) return;

    state = await AsyncValue.guard(() => _page(current.page + 1, current.items));
  }

  /// Marks one read in place - the list keeps its scroll - and updates the
  /// badge. Already-read messages cost nothing.
  Future<void> markRead(Message message) async {
    if (!message.isUnread) return;

    final updated = await ref.read(myInboxRepositoryProvider).markRead(message.id);
    final current = state.value;
    if (current != null) {
      state = AsyncData(
        current.copyWith(
          items: [
            for (final item in current.items)
              if (item.id == updated.id) updated else item,
          ],
        ),
      );
    }
    ref.invalidate(myUnreadCountProvider);
  }

  Future<int> markAllRead() async {
    final marked = await ref.read(myInboxRepositoryProvider).markAllRead();
    await refresh();
    return marked;
  }
}

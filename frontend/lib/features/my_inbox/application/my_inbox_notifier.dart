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
  const MyInbox({required this.items, required this.hasMore, required this.page, required this.unreadOnly});

  final List<Message> items;
  final bool hasMore;
  final int page;
  final bool unreadOnly;

  MyInbox copyWith({List<Message>? items}) =>
      MyInbox(items: items ?? this.items, hasMore: hasMore, page: page, unreadOnly: unreadOnly);
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

  @override
  Future<MyInbox> build() => _page(1, const []);

  Future<MyInbox> _page(int page, List<Message> before) async {
    final response = await ref
        .read(myInboxRepositoryProvider)
        .inbox(unreadOnly: _unreadOnly, page: page, perPage: perPage);

    return MyInbox(
      items: [...before, ...response.items],
      hasMore: response.currentPage < response.lastPage,
      page: response.currentPage,
      unreadOnly: _unreadOnly,
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

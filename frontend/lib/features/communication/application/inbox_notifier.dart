import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paged_list.dart';
import '../data/communication_repository.dart';
import '../data/models/message.dart';

final inboxNotifierProvider = AsyncNotifierProvider<InboxNotifier, PagedList<Message>>(InboxNotifier.new);

/// The signed-in user's own in-app messages. Every query is pinned to them
/// server-side, so there is no school or user filter here.
class InboxNotifier extends AsyncNotifier<PagedList<Message>> {
  bool _unreadOnly = false;
  int _page = 1;
  int _perPage = 20;

  bool get unreadOnly => _unreadOnly;

  @override
  Future<PagedList<Message>> build() => _fetch();

  Future<PagedList<Message>> _fetch() async {
    final response = await ref
        .read(communicationRepositoryProvider)
        .inbox(unreadOnly: _unreadOnly, page: _page, perPage: _perPage);

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

  Future<void> setUnreadOnly(bool unreadOnly) async {
    _unreadOnly = unreadOnly;
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

  Future<void> markRead(Message message) async {
    if (!message.isUnread) return;

    await ref.read(communicationRepositoryProvider).markRead(message.id);
    ref.invalidate(unreadCountProvider);
    await refresh();
  }

  Future<int> markAllRead() async {
    final marked = await ref.read(communicationRepositoryProvider).markAllRead();
    ref.invalidate(unreadCountProvider);
    await refresh();

    return marked;
  }
}

/// Drives the badge on the nav item. Cheap enough to re-read whenever the
/// inbox changes.
final unreadCountProvider = FutureProvider<int>((ref) => ref.watch(communicationRepositoryProvider).unreadCount());

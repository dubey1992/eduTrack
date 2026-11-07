import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/utils/date_format.dart';
import '../data/family_repository.dart';
import '../data/models/family_day.dart';
import '../data/models/family_records.dart';

/// Data with the moment it was fetched, so a screen that could not refresh
/// can keep showing it and say how old it is ("Updated 8:42 AM").
class Fetched<T> {
  const Fetched(this.data, this.at, {this.refreshFailure});

  final T data;
  final DateTime at;

  /// Set when the last refresh failed and [data] is the earlier copy.
  final Failure? refreshFailure;

  bool get isStale => refreshFailure != null;
}

/// One child's day, keyed by the child.
final familyTodayProvider = AsyncNotifierProvider.autoDispose.family<FamilyTodayNotifier, Fetched<FamilyToday>, int>(
  FamilyTodayNotifier.new,
  // A failure is shown with its own retry, not retried behind the parent's back.
  retry: (retryCount, error) => null,
);

class FamilyTodayNotifier extends AsyncNotifier<Fetched<FamilyToday>> {
  FamilyTodayNotifier(this.childId);

  final int childId;

  /// The day from the server; with no signal, the last copy on the phone,
  /// marked as old. Only with neither is it an error.
  @override
  Future<Fetched<FamilyToday>> build() async {
    final repository = ref.read(familyRepositoryProvider);
    try {
      return Fetched(await repository.today(childId), DateTime.now());
    } on Failure catch (failure) {
      if (!_isNoSignal(failure)) rethrow;

      final saved = await repository.savedToday(childId);
      if (saved == null) rethrow;
      return Fetched(saved.today, saved.at, refreshFailure: failure);
    }
  }

  static bool _isNoSignal(Failure failure) =>
      failure.code == Failure.network().code || failure.code == Failure.timeout().code;

  /// Pull to refresh. With no signal the last copy stays on screen, marked
  /// as old, rather than the day disappearing.
  Future<void> refresh() async {
    final previous = state.value;

    try {
      state = AsyncData(Fetched(await ref.read(familyRepositoryProvider).today(childId), DateTime.now()));
    } on Failure catch (failure) {
      state = previous == null
          ? AsyncError(failure, StackTrace.current)
          : AsyncData(Fetched(previous.data, previous.at, refreshFailure: failure));
    }
  }
}

/// One child's attendance for one month, keyed by (child, 'YYYY-MM').
final familyAttendanceProvider = AsyncNotifierProvider.autoDispose
    .family<FamilyAttendanceNotifier, AttendanceMonth, (int, String)>(
      FamilyAttendanceNotifier.new,
      retry: (retryCount, error) => null,
    );

class FamilyAttendanceNotifier extends AsyncNotifier<AttendanceMonth> {
  FamilyAttendanceNotifier(this.key);

  final (int, String) key;

  @override
  Future<AttendanceMonth> build() => ref.read(familyRepositoryProvider).attendance(key.$1, key.$2);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

/// The school's calendar for one month, keyed by 'YYYY-MM'.
final schoolCalendarProvider = AsyncNotifierProvider.autoDispose.family<SchoolCalendarNotifier, SchoolCalendar, String>(
  SchoolCalendarNotifier.new,
  retry: (retryCount, error) => null,
);

class SchoolCalendarNotifier extends AsyncNotifier<SchoolCalendar> {
  SchoolCalendarNotifier(this.month);

  final String month;

  @override
  Future<SchoolCalendar> build() => ref.read(familyRepositoryProvider).calendar(month);

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

/// The month a screen shows, written as the API wants it: 2026-11.
String monthKey(DateTime month) => apiDate(DateTime(month.year, month.month, 1)).substring(0, 7);

/// The school's messages, newest first, a page at a time.
class NoticesState {
  const NoticesState({required this.notices, required this.unreadCount, required this.hasMore, this.page = 1});

  final List<FamilyNotice> notices;
  final int unreadCount;
  final bool hasMore;
  final int page;
}

final familyNoticesProvider = AsyncNotifierProvider.autoDispose<FamilyNoticesNotifier, NoticesState>(
  FamilyNoticesNotifier.new,
  retry: (retryCount, error) => null,
);

class FamilyNoticesNotifier extends AsyncNotifier<NoticesState> {
  bool _loadingMore = false;

  @override
  Future<NoticesState> build() async {
    final page = await ref.read(familyRepositoryProvider).notices();
    return NoticesState(notices: page.notices, unreadCount: page.unreadCount, hasMore: page.hasMore);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// The next page, below the ones already shown. A second call while one
  /// is loading does nothing.
  Future<void> loadMore() async {
    final current = state.value;
    if (current == null || !current.hasMore || _loadingMore) return;

    _loadingMore = true;
    try {
      final next = await ref.read(familyRepositoryProvider).notices(page: current.page + 1);
      state = AsyncData(
        NoticesState(
          notices: [...current.notices, ...next.notices],
          unreadCount: next.unreadCount,
          hasMore: next.hasMore,
          page: current.page + 1,
        ),
      );
    } finally {
      _loadingMore = false;
    }
  }

  /// Opening a notice reads it. Shown read at once; the server is told after.
  Future<void> markRead(FamilyNotice notice) async {
    final current = state.value;
    if (current == null || notice.read) return;

    state = AsyncData(
      NoticesState(
        notices: [for (final n in current.notices) n.id == notice.id ? n.markedRead() : n],
        unreadCount: (current.unreadCount - 1).clamp(0, current.unreadCount),
        hasMore: current.hasMore,
        page: current.page,
      ),
    );
    await ref.read(familyRepositoryProvider).markRead(notice.id);
  }

  Future<void> markAllRead() async {
    await ref.read(familyRepositoryProvider).markAllRead();
    final current = state.value;
    if (current == null) return;

    state = AsyncData(
      NoticesState(
        notices: [for (final n in current.notices) n.markedRead()],
        unreadCount: 0,
        hasMore: current.hasMore,
        page: current.page,
      ),
    );
  }
}

/// The parent's switches for each kind of message.
final familyNotificationSettingsProvider =
    AsyncNotifierProvider.autoDispose<FamilyNotificationSettingsNotifier, FamilyNotificationSettings>(
      FamilyNotificationSettingsNotifier.new,
      retry: (retryCount, error) => null,
    );

class FamilyNotificationSettingsNotifier extends AsyncNotifier<FamilyNotificationSettings> {
  @override
  Future<FamilyNotificationSettings> build() => ref.read(familyRepositoryProvider).settings();

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }

  /// Flips one switch at once; puts it back, and throws, if the school's
  /// server did not take it.
  Future<void> set(String key, bool value) async {
    final before = state.value;
    if (before == null) return;

    state = AsyncData(before.withValue(key, value));
    try {
      state = AsyncData(await ref.read(familyRepositoryProvider).saveSetting(key, value));
    } on Failure {
      state = AsyncData(before);
      rethrow;
    }
  }
}

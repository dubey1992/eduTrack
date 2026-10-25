import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/teacher_day.dart';
import '../data/today_repository.dart';

/// No automatic retry: the screen offers its own Retry, and a refusal asked
/// again on a timer is the same refusal.
final todayProvider = AsyncNotifierProvider.autoDispose<TodayNotifier, TeacherDay>(
  TodayNotifier.new,
  retry: (retryCount, error) => null,
);

/// The teacher's day. Fetched when Today opens and again when it is pulled
/// down - the period under way moves on through the day, and the server is
/// the one that knows the school's clock.
class TodayNotifier extends AsyncNotifier<TeacherDay> {
  @override
  Future<TeacherDay> build() => ref.read(todayRepositoryProvider).today();

  /// Pull to refresh: keeps the day on screen while the new one loads, so the
  /// list does not blink to a spinner, and shows the error only if the
  /// refresh fails.
  Future<void> refresh() async {
    state = await AsyncValue.guard(build);
  }

  /// The retry button on the error view: back to the spinner.
  Future<void> retry() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(build);
  }
}

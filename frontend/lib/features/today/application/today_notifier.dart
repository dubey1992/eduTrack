import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../data/models/teacher_day.dart';
import '../data/today_repository.dart';

/// Riverpod's own retry is off: a refusal asked again on a timer is the same
/// refusal. The one thing worth asking again is "no signal" - the notifier
/// does that itself, below.
final todayProvider = AsyncNotifierProvider.autoDispose<TodayNotifier, TeacherDay>(
  TodayNotifier.new,
  retry: (retryCount, error) => null,
);

/// The teacher's day. Fetched when Today opens and again when it is pulled
/// down - the period under way moves on through the day, and the server is
/// the one that knows the school's clock.
///
/// With no signal, Today does not wait for somebody to find the Retry
/// button: it asks again every [offlineRetry], and as soon as the app comes
/// back to the front - the moment signal has most often returned
/// (docs/mobile-apps-review.md, 2.6).
class TodayNotifier extends AsyncNotifier<TeacherDay> {
  static const offlineRetry = Duration(seconds: 15);

  Timer? _again;

  @override
  Future<TeacherDay> build() {
    final lifecycle = AppLifecycleListener(
      onResume: () {
        if (state.hasError) unawaited(refresh());
      },
    );
    ref.onDispose(() {
      _again?.cancel();
      lifecycle.dispose();
    });

    return _fetch();
  }

  Future<TeacherDay> _fetch() async {
    _again?.cancel();
    try {
      return await ref.read(todayRepositoryProvider).today();
    } on Failure catch (failure) {
      if (failure.code == 'NETWORK_ERROR' && ref.mounted) _again = Timer(offlineRetry, refresh);
      rethrow;
    }
  }

  /// Pull to refresh: keeps the day on screen while the new one loads, so the
  /// list does not blink to a spinner, and shows the error only if the
  /// refresh fails.
  Future<void> refresh() async {
    final next = await AsyncValue.guard(_fetch);
    if (ref.mounted) state = next;
  }

  /// The retry button on the error view: back to the spinner.
  Future<void> retry() async {
    state = const AsyncLoading();
    final next = await AsyncValue.guard(_fetch);
    if (ref.mounted) state = next;
  }
}

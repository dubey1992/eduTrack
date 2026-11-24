import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/misc.dart' show ProviderListenable;

import '../../core/errors/failure.dart';
import '../../core/home_widget/home_screen_widget.dart';
import '../../core/home_widget/today_card.dart';
import '../../core/network/dio_client.dart';
import '../../core/security/app_lock.dart';
import '../../core/storage/key_value_store.dart';
import '../check_in/data/check_in_repository.dart';
import '../check_in/data/models/my_attendance_day.dart';
import '../family/application/family_today_card.dart';
import '../family/data/family_repository.dart';
import '../today/application/staff_today_card.dart';
import '../today/data/today_repository.dart';

/// Which app's card: also the background job's task name.
const staffWidgetApp = 'staff';
const familyWidgetApp = 'family';

/// Which child the Family widget is about, saved beside the card so the
/// background job asks about the same child the parent last looked at.
const widgetChildIdKey = 'today_child_id';
const widgetChildNameKey = 'today_child_name';

/// Reads a provider - a Ref's or a ProviderContainer's, so the same code
/// serves the running app and the background job.
typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// The card the widget should show now, or null to leave the last one up -
/// a refresh that failed on a bad signal keeps what was true, with its time.
///
/// Signed out and app lock come first and need no network: nothing about a
/// class or a child is fetched for a widget that must not show it.
Future<TodayCard?> currentTodayCard(Reader read, String app, DateTime now) async {
  if (await read(authTokenStorageProvider).readToken() == null) return const TodayCard.signedOut();
  if (await AppLockController.isEnabledIn(read(keyValueStoreProvider))) return const TodayCard.locked();

  try {
    if (app == staffWidgetApp) {
      final day = await read(todayRepositoryProvider).today();

      return staffTodayCard(day, await _myDay(read), now);
    }

    final widget = read(homeScreenWidgetProvider);
    final childId = int.tryParse(await widget.recall(widgetChildIdKey) ?? '');
    // The app has not said which child yet - it will, the next time it opens.
    if (childId == null) return null;
    final name = await widget.recall(widgetChildNameKey) ?? 'Today';

    return familyTodayCard(name, await read(familyRepositoryProvider).today(childId), now);
  } on Failure catch (failure) {
    if (failure.code == 'UNAUTHENTICATED') return const TodayCard.signedOut();

    debugPrint('Today widget: not refreshed (${failure.code})');
    return null;
  }
}

/// Checking in is a line of its own: a school without it, or a refusal,
/// leaves the line out instead of failing the whole card.
Future<MyAttendanceDay?> _myDay(Reader read) async {
  try {
    return await read(checkInRepositoryProvider).today();
  } on Failure catch (failure) {
    debugPrint('Today widget: no check-in line (${failure.code})');
    return null;
  }
}

/// Works out the card and puts it on the home screen.
Future<void> refreshTodayWidget(Reader read, String app, DateTime now) async {
  final card = await currentTodayCard(read, app, now);
  if (card != null) await read(homeScreenWidgetProvider).show(card);
}

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:workmanager/workmanager.dart';

import 'today_widget_refresh.dart';

/// The background job's entry point (docs/mobile-apps-review.md, M10):
/// Android runs it about every half hour while there is a network, in an
/// isolate of its own, with the task name saying which app's card to make.
///
/// It reads the same session and the same API the app does, through a
/// ProviderContainer of its own, and always reports success - a failed
/// refresh leaves the last card up with its time, and retrying at once on a
/// bad signal would only spend the battery.
@pragma('vm:entry-point')
void todayWidgetDispatcher() {
  Workmanager().executeTask((task, input) async {
    final container = ProviderContainer();
    try {
      await refreshTodayWidget(container.read, task, DateTime.now());
    } on Exception catch (error) {
      debugPrint('Today widget: background refresh failed: $error');
    } finally {
      container.dispose();
    }

    return true;
  });
}

/// Called once at start-up by the Staff and Family apps, before any job is
/// scheduled. Only Android has the widget.
Future<void> initialiseTodayWidget() async {
  if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;

  try {
    await Workmanager().initialize(todayWidgetDispatcher);
  } on Exception catch (error) {
    // The widget is a convenience; the app starts without it.
    debugPrint('Today widget: background refresh unavailable: $error');
  } on UnimplementedError {
    debugPrint('Today widget: background refresh unavailable here');
  }
}

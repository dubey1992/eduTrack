import 'package:flutter_foreground_task/flutter_foreground_task.dart';

/// Keeps the app alive while a trip is sharing its position.
///
/// Android stops a backgrounded app's timers, so without this the bus
/// vanishes from the office's map the moment the driver's screen sleeps -
/// which, in a cradle, is most of the run. A foreground service keeps the
/// process running and is the only way Android offers to say "this app is
/// doing something the person asked for".
///
/// Deliberately a *foreground* service and not background location: started
/// while the app is open, it needs no ACCESS_BACKGROUND_LOCATION, and so
/// none of Play's background-location review - a declaration form, a demo
/// video and weeks of calendar time (docs/driver-app.md, D4).
Future<void> start({required String title, required String body}) async {
  FlutterForegroundTask.init(
    androidNotificationOptions: AndroidNotificationOptions(
      channelId: 'trip_in_progress',
      channelName: 'Trip in progress',
      // Low: the notification has to be there, but it is a statement, not
      // an interruption. A driver does not need a sound every time.
      channelImportance: NotificationChannelImportance.LOW,
      priority: NotificationPriority.LOW,
    ),
    iosNotificationOptions: const IOSNotificationOptions(),
    foregroundTaskOptions: ForegroundTaskOptions(
      eventAction: ForegroundTaskEventAction.nothing(),
      autoRunOnBoot: false,
      allowWakeLock: true,
      allowWifiLock: false,
    ),
  );

  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.updateService(notificationTitle: title, notificationText: body);
    return;
  }

  await FlutterForegroundTask.startService(notificationTitle: title, notificationText: body);
}

Future<void> stop() async {
  if (await FlutterForegroundTask.isRunningService) await FlutterForegroundTask.stopService();
}

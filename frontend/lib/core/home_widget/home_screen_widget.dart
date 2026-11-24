import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:home_widget/home_widget.dart';
import 'package:workmanager/workmanager.dart';

import 'today_card.dart';

/// The Android widget's provider class, shared by the Staff and Family apps
/// and declared only in their manifests (android/app/src/{teacher,family}),
/// so the Bus app has no widget.
const todayWidgetProvider = 'com.school365ai.app.TodayWidgetProvider';

/// The one background job that keeps the widget fresh.
const todayWidgetJob = 'today-widget';

/// How often the background job runs. Android may stretch it to save
/// battery; it never runs more often than every 15 minutes.
const todayWidgetEvery = Duration(minutes: 30);

/// Runs a call to the native side, which a phone or test without the
/// plugin cannot serve. The widget is a convenience: it is never allowed to
/// break the app, so such a failure is logged and the app carries on.
Future<T?> _native<T>(String what, Future<T> Function() call) async {
  try {
    return await call();
  } on PlatformException catch (error) {
    debugPrint('Today widget: $what failed: ${error.code}');
  } on MissingPluginException {
    debugPrint('Today widget: $what is not available here');
  } on UnimplementedError {
    debugPrint('Today widget: $what is not available here');
  }
  return null;
}

/// Puts a card on the home screen. Swappable in tests.
abstract class HomeScreenWidget {
  Future<void> show(TodayCard card);

  /// A value saved beside the card - the Family app keeps which child the
  /// widget is about, so the background job asks for the same one.
  Future<void> remember(String key, String? value);

  Future<String?> recall(String key);
}

/// The real one: home_widget's shared storage, then a redraw. Only Android
/// has the widget; anywhere else this does nothing.
class AndroidHomeScreenWidget implements HomeScreenWidget {
  const AndroidHomeScreenWidget();

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> show(TodayCard card) async {
    if (!_supported) return;

    await _native('drawing the widget', () async {
      for (final entry in card.toWidgetData().entries) {
        await HomeWidget.saveWidgetData<String>(entry.key, entry.value);
      }
      await HomeWidget.updateWidget(qualifiedAndroidName: todayWidgetProvider);
    });
  }

  @override
  Future<void> remember(String key, String? value) async {
    if (_supported) await _native('saving $key', () => HomeWidget.saveWidgetData<String>(key, value));
  }

  @override
  Future<String?> recall(String key) async =>
      _supported ? _native<String?>('reading $key', () => HomeWidget.getWidgetData<String>(key)) : null;
}

final homeScreenWidgetProvider = Provider<HomeScreenWidget>((ref) => const AndroidHomeScreenWidget());

/// Starts and stops the background refresh. Swappable in tests.
abstract class TodayWidgetScheduler {
  /// Every [todayWidgetEvery] while there is a network, as [app].
  Future<void> start(String app);

  Future<void> stop();
}

class WorkmanagerTodayWidgetScheduler implements TodayWidgetScheduler {
  const WorkmanagerTodayWidgetScheduler();

  bool get _supported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  Future<void> start(String app) async {
    if (!_supported) return;

    await _native(
      'starting the background refresh',
      () => Workmanager().registerPeriodicTask(
        todayWidgetJob,
        app,
        frequency: todayWidgetEvery,
        constraints: Constraints(networkType: NetworkType.connected),
        // Signing in again keeps the job already running rather than
        // restarting its clock.
        existingWorkPolicy: ExistingPeriodicWorkPolicy.keep,
      ),
    );
  }

  @override
  Future<void> stop() async {
    if (!_supported) return;

    await _native('stopping the background refresh', () => Workmanager().cancelByUniqueName(todayWidgetJob));
  }
}

final todayWidgetSchedulerProvider = Provider<TodayWidgetScheduler>((ref) => const WorkmanagerTodayWidgetScheduler());

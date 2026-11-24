import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/home_widget/home_screen_widget.dart';
import '../../core/home_widget/today_card.dart';
import '../../core/security/app_lock.dart';
import 'today_widget_refresh.dart';
import '../../core/l10n/app_language.dart';

/// Keeps the home-screen widget in step with the running app
/// (docs/mobile-apps-review.md, M10). Sits above the app's pages, like
/// RegisterSender.
///
/// - Signed in: starts the half-hourly background job and refreshes now.
/// - Signed out: stops the job and puts "Sign in" on the widget, so nothing
///   of the last person's day is left on the home screen.
/// - Back in the app, or the app lock switched: refreshes.
/// - [onChange] lets the app refresh when its own data moves (the Today
///   screen reloading, another child picked) - called with a debounced
///   refresh, so a burst of changes is one fetch.
///
/// [signedIn] is null while the session is still being read: nothing is
/// done then, or every start of the app would flash "Sign in" and stop the
/// job before the session came back.
class TodayWidgetSync extends ConsumerStatefulWidget {
  const TodayWidgetSync({
    super.key,
    required this.app,
    required this.signedIn,
    required this.child,
    this.onChange,
    this.beforeRefresh,
  });

  final String app;
  final bool? signedIn;
  final Widget child;
  final void Function(WidgetRef ref, VoidCallback refresh)? onChange;

  /// Runs before each refresh - the Family app saves which child the
  /// widget is about, for this refresh and the background job's.
  final Future<void> Function(WidgetRef ref)? beforeRefresh;

  @override
  ConsumerState<TodayWidgetSync> createState() => _TodayWidgetSyncState();
}

class _TodayWidgetSyncState extends ConsumerState<TodayWidgetSync> {
  static const debounce = Duration(seconds: 1);

  late final AppLifecycleListener _lifecycle;
  Timer? _soon;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(onResume: _refreshSoon);
    WidgetsBinding.instance.addPostFrameCallback((_) => _apply(null, widget.signedIn));
  }

  @override
  void didUpdateWidget(TodayWidgetSync old) {
    super.didUpdateWidget(old);
    if (old.signedIn != widget.signedIn) _apply(old.signedIn, widget.signedIn);
  }

  @override
  void dispose() {
    _soon?.cancel();
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _apply(bool? before, bool? now) async {
    if (now == null || !mounted) return;
    final scheduler = ref.read(todayWidgetSchedulerProvider);

    if (now) {
      await scheduler.start(widget.app);
      _refreshSoon();
      return;
    }

    // Only on a real sign-out, or a start with nobody signed in.
    if (before != false) {
      _soon?.cancel();
      await scheduler.stop();
      final l10n = await widgetLocalizations(ref.read);
      if (!mounted) return;
      await ref.read(homeScreenWidgetProvider).show(TodayCard.signedOut(l10n));
    }
  }

  void _refreshSoon() {
    if (widget.signedIn != true) return;
    _soon?.cancel();
    _soon = Timer(debounce, () async {
      if (!mounted) return;
      await widget.beforeRefresh?.call(ref);
      if (mounted) await refreshTodayWidget(ref.read, widget.app, DateTime.now());
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(appLockProvider.select((lock) => lock.enabled), (_, _) => _refreshSoon());
    // Another language picked in the app: the widget follows (M11).
    ref.listen(appLanguageProvider, (_, _) => _refreshSoon());
    if (widget.signedIn == true) widget.onChange?.call(ref, _refreshSoon);

    return widget.child;
  }
}

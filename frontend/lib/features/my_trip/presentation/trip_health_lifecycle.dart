import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/trip_health_log.dart';

/// Notes in the trip log each time the phone puts the app in the background
/// and brings it back (docs/mobile-apps-review.md, M0). A run with the
/// screen off is a run in the background; the log shows whether positions
/// kept coming while it was.
class TripHealthLifecycle extends ConsumerStatefulWidget {
  const TripHealthLifecycle({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<TripHealthLifecycle> createState() => _TripHealthLifecycleState();
}

class _TripHealthLifecycleState extends ConsumerState<TripHealthLifecycle> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final kind = switch (state) {
      AppLifecycleState.paused => TripHealthKind.appPaused,
      AppLifecycleState.resumed => TripHealthKind.appResumed,
      _ => null,
    };

    if (kind != null) ref.read(tripHealthLogProvider).add(kind);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

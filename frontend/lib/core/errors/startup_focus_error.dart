import 'package:flutter/foundation.dart';

/// Keeps one known, harmless framework error out of the browser console
/// (found 2026-11-05 from a customer-visible console).
///
/// When the browser hands the page focus before Flutter has laid out its
/// first frame - on load, or just after signing in rebuilds the screen -
/// Flutter's view picks a widget to focus by reading every candidate's
/// position, and a widget with no size yet throws "RenderBox was not laid
/// out". Nothing breaks: focus simply stays where it was, and the next frame
/// lays everything out. The policy doing it is fixed inside Flutter's View,
/// so the app cannot hand it a different one.
///
/// Only that error is held back - matched on Flutter's own description of
/// where it came from - and everything else reaches [next] untouched.
void installStartupFocusErrorFilter() {
  final next = FlutterError.onError;

  FlutterError.onError = (details) {
    if (isStartupFocusError(details)) {
      debugPrint('Ignored a focus request made before the first layout.');
      return;
    }

    next?.call(details);
  };
}

/// Whether [details] is the view-focus error described above.
bool isStartupFocusError(FlutterErrorDetails details) {
  final where = details.context?.toDescription() ?? '';

  return where.contains('didChangeViewFocus') && details.exceptionAsString().contains('was not laid out');
}

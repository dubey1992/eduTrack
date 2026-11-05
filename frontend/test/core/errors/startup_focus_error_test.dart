import 'package:edutrack_app/core/errors/startup_focus_error.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

FlutterErrorDetails details(Object error, String where) =>
    FlutterErrorDetails(exception: error, library: 'widgets library', context: ErrorDescription(where));

/// The one harmless startup error the web app keeps out of the console.
void main() {
  const viewFocus = 'while dispatching notifications for WidgetsBindingObserver.didChangeViewFocus';

  test('the view-focus error before the first layout is recognised', () {
    expect(isStartupFocusError(details(StateError('RenderBox was not laid out: RenderStack#1'), viewFocus)), isTrue);
  });

  test('the same words from anywhere else are not', () {
    expect(
      isStartupFocusError(details(StateError('RenderBox was not laid out: RenderStack#1'), 'during performLayout()')),
      isFalse,
    );
  });

  test('any other error during a view-focus change is not', () {
    expect(isStartupFocusError(details(StateError('Something else'), viewFocus)), isFalse);
  });

  test('installed, it holds that error back and passes every other one on', () {
    final previous = FlutterError.onError;
    addTearDown(() => FlutterError.onError = previous);
    final seen = <FlutterErrorDetails>[];
    FlutterError.onError = seen.add;

    installStartupFocusErrorFilter();
    FlutterError.onError!(details(StateError('RenderBox was not laid out: RenderStack#1'), viewFocus));
    final real = details(StateError('A real bug'), 'during build');
    FlutterError.onError!(real);

    expect(seen, [real]);
  });
}

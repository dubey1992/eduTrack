import 'package:edutrack_app/features/maps/presentation/map_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A map ignores clicks meant for a dialog drawn over it (the web draws the
/// map underneath Flutter, so those clicks reach it too).
void main() {
  Widget app(GlobalKey<NavigatorState> navigator) => MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [MapCover.instance],
    home: const Scaffold(body: Text('page')),
  );

  testWidgets('a page under an open dialog is covered; the dialog itself is not', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(navigator));
    final page = ModalRoute.of(tester.element(find.text('page')));

    showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: Text('form')),
    );
    await tester.pumpAndSettle();
    final dialog = ModalRoute.of(tester.element(find.text('form')));

    expect(MapCover.instance.covers(page), isTrue);
    expect(MapCover.instance.covers(dialog), isFalse);

    navigator.currentState!.pop();
    await tester.pumpAndSettle();
  });

  testWidgets('a click right after the dialog closes still counts as meant for it', (tester) async {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(app(navigator));
    final page = ModalRoute.of(tester.element(find.text('page')));

    showDialog<void>(
      context: navigator.currentContext!,
      builder: (_) => const AlertDialog(content: Text('form')),
    );
    await tester.pumpAndSettle();
    navigator.currentState!.pop();
    await tester.pumpAndSettle();

    expect(MapCover.instance.covers(page), isTrue);
  });
}

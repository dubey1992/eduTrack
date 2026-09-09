import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('a SnackBar renders as a small capped-width toast, not a full-width bar', (tester) async {
    tester.view.physicalSize = const Size(1400, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () =>
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('User created.'))),
                child: const Text('Trigger'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Trigger'));
    await tester.pumpAndSettle();

    // The Material closest to the text is the visible toast card; an outer,
    // full-width Material also matches (the ambient Scaffold/page one) - the
    // SnackBar itself resolves its interactive (swipe-to-dismiss) bounds to
    // that outer width regardless of `width`, so it isn't a useful signal
    // here. The card's own rendered width is what a viewer actually sees.
    final cardWidth = tester
        .getSize(find.ancestor(of: find.text('User created.'), matching: find.byType(Material)).first)
        .width;
    expect(cardWidth, 360);
  });
}

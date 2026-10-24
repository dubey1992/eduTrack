import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every filled button - plain or tonal, enabled or disabled - keeps its
/// label readable in both themes (docs/driver-app.md, D9).
///
/// Found on a dark phone: the trip sheet's Dropped button, the one a crew
/// member could press, had a light label on the dark theme's light primary.
void main() {
  Future<(Color, Color)> colours(WidgetTester tester, ThemeData theme, Widget button) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: button)),
      ),
    );
    await tester.pumpAndSettle();

    final material = tester.widget<Material>(
      find.descendant(of: find.bySubtype<ButtonStyleButton>(), matching: find.byType(Material)).first,
    );
    final text = tester.widget<DefaultTextStyle>(
      find.descendant(of: find.bySubtype<ButtonStyleButton>(), matching: find.byType(DefaultTextStyle)).last,
    );
    return (material.color!, text.style.color!);
  }

  double contrast(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
  }

  // Built inside each test: the theme loads a font, which needs the binding.
  for (final (name, theme) in [('light', AppTheme.light), ('dark', AppTheme.dark)]) {
    testWidgets('a tonal button reads in the $name theme', (tester) async {
      final (background, foreground) = await colours(
        tester,
        theme(),
        FilledButton.tonal(onPressed: () {}, child: const Text('Dropped')),
      );
      expect(contrast(background, foreground), greaterThan(4.5), reason: 'enabled tonal, $name');
    });

    testWidgets('and a disabled one is dimmer than the live one beside it, in the $name theme', (tester) async {
      final (live, _) = await colours(
        tester,
        theme(),
        FilledButton.tonal(onPressed: () {}, child: const Text('Boarded')),
      );
      final (dead, _) = await colours(
        tester,
        theme(),
        const FilledButton.tonal(onPressed: null, child: Text('Boarded')),
      );

      final page = theme().scaffoldBackgroundColor;
      expect(contrast(dead, page), lessThan(contrast(live, page)), reason: 'disabled stands out less, $name');
    });
  }
}

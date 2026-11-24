import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/presentation/widgets/auth_card.dart';
import 'package:edutrack_app/features/auth/presentation/widgets/auth_palette.dart';
import 'package:edutrack_app/features/auth/presentation/widgets/custom_text_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The sign-in screens follow the phone's theme.
///
/// They used to be built from light-only constants, so a dark phone got a
/// white card with the theme's dark input boxes inside it (found on the
/// driver app, docs/driver-app.md). Now the card, the fields and the page
/// take their colours from one palette chosen per brightness.
void main() {
  Future<void> pump(WidgetTester tester, ThemeData theme, Widget child) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Scaffold(body: Center(child: child)),
      ),
    );
    // A theme change is animated, so one frame still reads the old colours.
    await tester.pumpAndSettle();
  }

  Color cardColour(WidgetTester tester) {
    final box = tester.widget<Container>(find.byKey(const Key('auth-card'))).decoration! as BoxDecoration;
    return box.color!;
  }

  Color fieldFill(WidgetTester tester) {
    return tester.widget<TextField>(find.byType(TextField)).decoration!.fillColor!;
  }

  testWidgets("in the web app's light theme the card is white on the ivory page", (tester) async {
    await pump(tester, AppTheme.light(), const AuthCard(child: SizedBox(height: 20)));

    expect(cardColour(tester), AuthPalette.brandLight.surface);
    expect(AuthPalette.of(tester.element(find.byType(AuthCard))), AuthPalette.brandLight);
  });

  testWidgets('in the dark theme the card is a dark surface, not a white block', (tester) async {
    await pump(tester, AppTheme.dark(), const AuthCard(child: SizedBox(height: 20)));

    expect(cardColour(tester), AuthPalette.brandDark.surface);
    expect(cardColour(tester).computeLuminance(), lessThan(0.1));
  });

  testWidgets('and the fields match the card they sit in, in both themes', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pump(tester, AppTheme.light(), CustomTextField(controller: controller, label: 'Email'));
    expect(fieldFill(tester), AuthPalette.brandLight.surface);

    await pump(tester, AppTheme.dark(), CustomTextField(controller: controller, label: 'Email'));
    expect(fieldFill(tester), AuthPalette.brandDark.surface);
  });

  // Since slice B1 (2026-11-24) every phone app signs in on the School365AI
  // design, as the web app does (docs/mobile-apps-review.md).
  for (final (app, light, dark) in [
    ('Driver', AppTheme.crewLight, AppTheme.crewDark),
    ('Staff', AppTheme.teacherLight, AppTheme.teacherDark),
  ]) {
    testWidgets('the $app app signs in on the School365AI design, in both themes', (tester) async {
      await pump(tester, light(), const AuthCard(child: SizedBox(height: 20)));
      expect(cardColour(tester), AuthPalette.brandLight.surface);
      expect(AuthPalette.of(tester.element(find.byType(AuthCard))), AuthPalette.brandLight);

      await pump(tester, dark(), const AuthCard(child: SizedBox(height: 20)));
      expect(cardColour(tester), AuthPalette.brandDark.surface);
    });
  }

  test('each dark palette lightens its accent and its text', () {
    expect(AuthPalette.dark.primary.computeLuminance(), greaterThan(AuthPalette.light.primary.computeLuminance()));
    expect(
      AuthPalette.brandDark.primary.computeLuminance(),
      greaterThan(AuthPalette.brandLight.primary.computeLuminance()),
    );
    expect(AuthPalette.dark.text.computeLuminance(), greaterThan(0.8));
    expect(AuthPalette.brandDark.text.computeLuminance(), greaterThan(0.8));
    expect(AuthPalette.light.text.computeLuminance(), lessThan(0.1));
    expect(AuthPalette.brandLight.text.computeLuminance(), lessThan(0.1));
  });
}

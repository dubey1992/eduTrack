import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/presentation/widgets/auth_card.dart';
import 'package:edutrack_app/features/auth/presentation/widgets/auth_palette.dart';
import 'package:edutrack_app/features/auth/presentation/widgets/custom_text_field.dart';
import 'package:edutrack_app/features/marketing/presentation/marketing_colors.dart';
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

  testWidgets('in the light theme the card is the marketing white, as on the web', (tester) async {
    await pump(tester, AppTheme.light(), const AuthCard(child: SizedBox(height: 20)));

    expect(cardColour(tester), MarketingColors.surface);
  });

  testWidgets('in the dark theme the card is a dark surface, not a white block', (tester) async {
    await pump(tester, AppTheme.dark(), const AuthCard(child: SizedBox(height: 20)));

    expect(cardColour(tester), AuthPalette.dark.surface);
    expect(cardColour(tester).computeLuminance(), lessThan(0.1));
  });

  testWidgets('and the fields match the card they sit in, in both themes', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await pump(tester, AppTheme.light(), CustomTextField(controller: controller, label: 'Email'));
    expect(fieldFill(tester), MarketingColors.surface);

    await pump(tester, AppTheme.dark(), CustomTextField(controller: controller, label: 'Email'));
    expect(fieldFill(tester), AuthPalette.dark.surface);
  });

  test('the dark palette keeps the brand blue and lightens the text', () {
    expect(AuthPalette.dark.primary.computeLuminance(), greaterThan(AuthPalette.light.primary.computeLuminance()));
    expect(AuthPalette.dark.text.computeLuminance(), greaterThan(0.8));
    expect(AuthPalette.light.text.computeLuminance(), lessThan(0.1));
  });
}

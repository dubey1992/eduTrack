import 'package:edutrack_app/core/theme/app_colors.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/theme/chart_palette.dart';
import 'package:edutrack_app/features/setup_guide/presentation/widgets/setup_progress_bar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> pump(WidgetTester tester, int done, {int total = 6, ThemeData? theme}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.light(),
      home: Scaffold(
        body: SizedBox(
          width: 600,
          child: SetupProgressBar(done: done, total: total),
        ),
      ),
    ),
  );
}

Color? stepColour(WidgetTester tester, int step) =>
    (tester.widget<Container>(find.byKey(Key('setup-step-$step'))).decoration as BoxDecoration).color;

/// The setup guide's bar (decided 2026-11-04): a segment per step, the done
/// ones coloured by how far setup has got, the rest grey.
void main() {
  testWidgets('has a segment per step', (tester) async {
    await pump(tester, 2);

    for (var step = 0; step < 6; step++) {
      expect(find.byKey(Key('setup-step-$step')), findsOneWidget);
    }
    expect(find.byKey(const Key('setup-step-6')), findsNothing);
  });

  testWidgets('under halfway the done steps are orange and the rest grey', (tester) async {
    await pump(tester, 2);

    expect(stepColour(tester, 0), ChartPalette.orange.light);
    expect(stepColour(tester, 1), ChartPalette.orange.light);
    expect(stepColour(tester, 2), isNot(ChartPalette.orange.light));
    expect(stepColour(tester, 5), stepColour(tester, 2), reason: 'every step still to do looks the same');
  });

  testWidgets('from halfway they turn blue', (tester) async {
    await pump(tester, 3);

    expect(stepColour(tester, 2), ChartPalette.blue.light);
    expect(stepColour(tester, 3), isNot(ChartPalette.blue.light));
  });

  testWidgets('every step done is green all the way', (tester) async {
    await pump(tester, 6);

    for (var step = 0; step < 6; step++) {
      expect(stepColour(tester, step), AppColors.light.success);
    }
  });

  testWidgets('nothing done yet is all grey', (tester) async {
    await pump(tester, 0);

    final grey = stepColour(tester, 0);
    for (var step = 1; step < 6; step++) {
      expect(stepColour(tester, step), grey);
    }
    expect(grey, isNot(anyOf(ChartPalette.orange.light, ChartPalette.blue.light, AppColors.light.success)));
  });

  testWidgets('takes the dark shades in the dark theme', (tester) async {
    await pump(tester, 1, theme: AppTheme.dark());

    expect(stepColour(tester, 0), ChartPalette.orange.dark);
  });

  testWidgets('says how far it has got to a screen reader', (tester) async {
    await pump(tester, 4);

    expect(find.bySemanticsLabel('4 of 6 setup steps done'), findsOneWidget);
  });
}

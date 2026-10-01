import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/marketing/data/marketing_defaults.dart';
import 'package:edutrack_app/features/marketing/data/models/marketing_draft.dart';
import 'package:edutrack_app/features/marketing/presentation/widgets/marketing_list_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const stats = MarketingListField(
  key: 'hero.stats',
  label: 'The figures under the hero',
  itemLabel: 'Figure',
  help: 'Five across the width of the hero.',
  fields: [
    MarketingItemField(key: 'value', label: 'Figure', maxLength: 16, help: '', choices: []),
    MarketingItemField(key: 'label', label: 'What it is', maxLength: 24, help: '', choices: []),
  ],
  minItems: 1,
  maxItems: 3,
);

const cards = MarketingListField(
  key: 'features.items',
  label: 'The feature cards',
  itemLabel: 'Card',
  help: '',
  fields: [
    MarketingItemField(
      key: 'icon',
      label: 'Icon',
      maxLength: 4,
      help: '',
      choices: [
        MarketingChoice(value: '☺', label: 'Face'),
        MarketingChoice(value: '✓', label: 'Tick'),
      ],
    ),
    MarketingItemField(key: 'title', label: 'Title', maxLength: 28, help: '', choices: []),
  ],
  minItems: 1,
  maxItems: 4,
);

/// The last thing [MarketingListEditor] reported. Checking this rather than
/// the boxes is the point: what the screen sends is what it reports.
late List<Map<String, String>> reported;

Widget wrap(
  MarketingListField declared,
  List<Map<String, String>> initial, {
  bool enabled = true,
  String? serverError,
}) {
  reported = initial;

  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Form(
          child: MarketingListEditor(
            declared: declared,
            initial: initial,
            onChanged: (items) => reported = items,
            enabled: enabled,
            serverError: serverError,
          ),
        ),
      ),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1200, 2200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The button behind a tooltip - [find.byTooltip] finds the Tooltip the
/// IconButton builds inside itself, not the button.
IconButton iconButton(WidgetTester tester, String tooltip) {
  return tester.widget<IconButton>(find.ancestor(of: find.byTooltip(tooltip), matching: find.byType(IconButton)).first);
}

Future<void> tapTooltip(WidgetTester tester, String tooltip) async {
  await tester.ensureVisible(find.byTooltip(tooltip));
  await tester.tap(find.byTooltip(tooltip));
  await tester.pumpAndSettle();
}

/// The repeating lists on the homepage (docs/marketing-content.md, slice 3).
void main() {
  group('showing a list', () {
    testWidgets('it draws a card per item, in order', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(stats, [
          {'value': '500+', 'label': 'Schools'},
          {'value': 'Global', 'label': 'Reach'},
        ]),
      );

      expect(find.text('Figure 1 of 2'), findsOneWidget);
      expect(find.text('Figure 2 of 2'), findsOneWidget);
      expect(find.widgetWithText(TextFormField, '500+'), findsOneWidget);
    });

    testWidgets('it says how much room is left', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(stats, [
          {'value': '500+', 'label': 'Schools'},
        ]),
      );

      expect(find.text('1 of 3'), findsOneWidget);
    });

    testWidgets('a field with a fixed set is a picker, not a box', (tester) async {
      // Free text lets somebody type a character the font has no glyph
      // for, and the card draws an empty box where the icon belongs.
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(cards, [
          {'icon': '☺', 'title': 'Attendance'},
        ]),
      );

      expect(find.byType(DropdownButtonFormField<String>), findsOneWidget);
      expect(find.widgetWithText(TextFormField, 'Attendance'), findsOneWidget);
    });

    testWidgets("the server's complaint about the list is shown above it", (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(stats, [
          {'value': '500+', 'label': 'Schools'},
        ], serverError: 'The figures under the hero holds 5 at most - there are 6.'),
      );

      expect(find.text('The figures under the hero holds 5 at most - there are 6.'), findsOneWidget);
    });
  });

  group('adding and removing', () {
    testWidgets('adding appends an empty item', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '500+', 'label': 'Schools'},
        ]),
      );

      await tester.tap(find.text('Add figure'));
      await tester.pumpAndSettle();

      expect(find.text('Figure 2 of 2'), findsOneWidget);
      expect(reported, [
        {'value': '500+', 'label': 'Schools'},
        {'value': '', 'label': ''},
      ]);
    });

    testWidgets('a new item in a picker starts on the first choice, not blank', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(cards, [
          {'icon': '✓', 'title': 'Attendance'},
        ]),
      );

      await tester.tap(find.text('Add card'));
      await tester.pumpAndSettle();

      expect(reported.last['icon'], '☺');
    });

    testWidgets('once the design is full, nothing more may be added', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '1', 'label': 'One'},
          {'value': '2', 'label': 'Two'},
          {'value': '3', 'label': 'Three'},
        ]),
      );

      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Add figure')).onPressed, isNull);
      expect(find.text('3 is as many as the design holds.'), findsOneWidget);
    });

    testWidgets('removing takes that item out and renumbers the rest', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '1', 'label': 'One'},
          {'value': '2', 'label': 'Two'},
        ]),
      );

      await tapTooltip(tester, 'Remove Figure 1');

      expect(reported, [
        {'value': '2', 'label': 'Two'},
      ]);
      expect(find.text('Figure 1 of 1'), findsOneWidget);
    });

    testWidgets('the last one cannot be removed, and says why', (tester) async {
      // An empty grid is a hole in the page, and the server refuses it.
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '1', 'label': 'One'},
        ]),
      );

      expect(find.byTooltip('The page needs at least one figure'), findsOneWidget);
      expect(iconButton(tester, 'The page needs at least one figure').onPressed, isNull);
    });
  });

  group('reordering', () {
    testWidgets('moving one down swaps it with the next', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '1', 'label': 'One'},
          {'value': '2', 'label': 'Two'},
        ]),
      );

      await tapTooltip(tester, 'Move Figure 1 down');

      expect(reported, [
        {'value': '2', 'label': 'Two'},
        {'value': '1', 'label': 'One'},
      ]);
    });

    testWidgets('moving one up swaps it with the one before', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '1', 'label': 'One'},
          {'value': '2', 'label': 'Two'},
        ]),
      );

      await tapTooltip(tester, 'Move Figure 2 up');

      expect(reported.first['value'], '2');
    });

    testWidgets('the first cannot go up and the last cannot go down', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '1', 'label': 'One'},
          {'value': '2', 'label': 'Two'},
        ]),
      );

      expect(iconButton(tester, 'Move Figure 1 up').onPressed, isNull);
      expect(iconButton(tester, 'Move Figure 2 down').onPressed, isNull);
    });

    testWidgets('typing survives a move, in the row it was typed in', (tester) async {
      // The controllers belong to the row, so they travel with it. Without
      // that, reordering mid-sentence drops the cursor into another row.
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '1', 'label': 'One'},
          {'value': '2', 'label': 'Two'},
        ]),
      );

      await tester.enterText(find.widgetWithText(TextFormField, '1'), 'Rewritten');
      await tester.pump();
      await tapTooltip(tester, 'Move Figure 1 down');

      expect(reported, [
        {'value': '2', 'label': 'Two'},
        {'value': 'Rewritten', 'label': 'One'},
      ]);
    });
  });

  group('going back to the words that ship', () {
    testWidgets('it puts the shipped list back', (tester) async {
      // The equivalent of clearing a box, which for a whole list has to be
      // an action - there is nowhere to show a placeholder.
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': 'Changed', 'label': 'Entirely'},
        ]),
      );

      await tester.tap(find.text('Use the ones that ship'));
      await tester.pumpAndSettle();

      expect(reported, marketingListDefaults['hero.stats']);
    });
  });

  group('while the form is busy', () {
    testWidgets('nothing may be added, removed, moved or reverted', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '1', 'label': 'One'},
          {'value': '2', 'label': 'Two'},
        ], enabled: false),
      );

      expect(tester.widget<OutlinedButton>(find.widgetWithText(OutlinedButton, 'Add figure')).onPressed, isNull);
      expect(iconButton(tester, 'Remove Figure 1').onPressed, isNull);
      expect(iconButton(tester, 'Move Figure 1 down').onPressed, isNull);
      expect(tester.widget<TextButton>(find.widgetWithText(TextButton, 'Use the ones that ship')).onPressed, isNull);
    });
  });

  group('what the form refuses before asking the server', () {
    Future<bool> validate(WidgetTester tester) async {
      final form = tester.state<FormState>(find.byType(Form));
      final valid = form.validate();
      await tester.pumpAndSettle();

      return valid;
    }

    testWidgets('a blank box inside an item is refused', (tester) async {
      // Not a fallback to anything: a figure with no label is a gap in a
      // row of five.
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '500+', 'label': ''},
        ]),
      );

      expect(await validate(tester), isFalse);
      expect(find.text('Every Figure needs a what it is.'), findsOneWidget);
    });

    testWidgets('a value too long for its slot is refused', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '500+', 'label': 'x' * 25},
        ]),
      );

      expect(await validate(tester), isFalse);
      expect(find.text('What it is must be 24 characters or fewer - it is 25.'), findsOneWidget);
    });

    testWidgets('a list everybody filled in properly passes', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(stats, [
          {'value': '500+', 'label': 'Schools'},
          {'value': 'Global', 'label': 'Reach'},
        ]),
      );

      expect(await validate(tester), isTrue);
    });
  });
}

import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/searchable_dropdown.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _sections = [
  'Playgroup A', 'Nursery A', 'LKG A', 'UKG A', 'Class 1 A', 'Class 1 B', 'Class 2 A', 'Class 2 B', //
  'Class 3 A', 'Class 9 A', 'Class 10 A', 'Class 12 A',
];

Future<List<int?>> _pump(
  WidgetTester tester,
  List<String> labels, {
  int? initial,
  FormFieldValidator<int>? validator,
}) async {
  final chosen = <int?>[];
  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Form(
          child: Builder(
            builder: (context) => Column(
              children: [
                SearchableDropdown<int>(
                  initialValue: initial,
                  decoration: const InputDecoration(labelText: 'Class'),
                  items: [for (var i = 0; i < labels.length; i++) DropdownMenuItem(value: i, child: Text(labels[i]))],
                  onChanged: chosen.add,
                  validator: validator,
                ),
                TextButton(onPressed: () => Form.of(context).validate(), child: const Text('Check')),
              ],
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return chosen;
}

/// Long dropdowns can be searched (asked for 2026-11-05).
void main() {
  testWidgets('a short list stays the ordinary dropdown', (tester) async {
    await _pump(tester, ['Term 1', 'Term 2', 'Term 3']);

    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(find.byKey(const Key('searchable-dropdown')), findsNothing);
  });

  testWidgets('a long list opens a search box over the list', (tester) async {
    await _pump(tester, _sections);

    await tester.tap(find.byKey(const Key('searchable-dropdown')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('searchable-dropdown-search')), findsOneWidget);
    expect(find.text('Playgroup A'), findsOneWidget);
  });

  testWidgets('typing narrows it, matching any part of the words and any case', (tester) async {
    await _pump(tester, _sections);
    await tester.tap(find.byKey(const Key('searchable-dropdown')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('searchable-dropdown-search')), 'class 1 b');
    await tester.pumpAndSettle();

    expect(find.text('Class 1 B'), findsOneWidget);
    expect(find.text('Class 1 A'), findsNothing);
    expect(find.text('Nursery A'), findsNothing);
  });

  testWidgets('choosing one fills the field and tells the screen', (tester) async {
    final chosen = await _pump(tester, _sections);
    await tester.tap(find.byKey(const Key('searchable-dropdown')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('searchable-dropdown-search')), '12');
    await tester.pumpAndSettle();

    await tester.tap(find.text('Class 12 A'));
    await tester.pumpAndSettle();

    expect(chosen, [11]);
    expect(find.text('Class 12 A'), findsOneWidget);
    expect(find.byKey(const Key('searchable-dropdown-search')), findsNothing);
  });

  testWidgets('nothing matching says so', (tester) async {
    await _pump(tester, _sections);
    await tester.tap(find.byKey(const Key('searchable-dropdown')));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('searchable-dropdown-search')), 'Class 99');
    await tester.pumpAndSettle();

    expect(find.text('Nothing matches "Class 99".'), findsOneWidget);
  });

  testWidgets('cancelling leaves the choice as it was', (tester) async {
    final chosen = await _pump(tester, _sections, initial: 4);
    await tester.tap(find.byKey(const Key('searchable-dropdown')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(chosen, isEmpty);
    expect(find.text('Class 1 A'), findsOneWidget);
  });

  testWidgets('the form check still runs, and shows its message on the field', (tester) async {
    await _pump(tester, _sections, validator: (value) => value == null ? 'Choose a class.' : null);

    await tester.tap(find.text('Check'));
    await tester.pumpAndSettle();

    expect(find.text('Choose a class.'), findsOneWidget);
  });
}

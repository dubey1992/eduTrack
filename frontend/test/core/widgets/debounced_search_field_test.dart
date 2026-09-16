import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/debounced_search_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The search box every fetching list uses.
///
/// Wired straight to onChanged, a search box asks the server once per
/// keystroke; the replies can then arrive in any order, so the list settles on
/// the answer to a prefix nobody wanted.
void main() {
  late TextEditingController controller;
  late List<String> searches;

  setUp(() {
    controller = TextEditingController();
    searches = [];
  });

  tearDown(() => controller.dispose());

  Widget wrap() {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: DebouncedSearchField(controller: controller, label: 'Search', onSearch: searches.add),
      ),
    );
  }

  testWidgets('says nothing while the typing is still going', (tester) async {
    await tester.pumpWidget(wrap());

    for (final prefix in ['A', 'Ab', 'Abh', 'Abhi']) {
      await tester.enterText(find.byType(TextField), prefix);
      await tester.pump(const Duration(milliseconds: 100));
    }

    expect(searches, isEmpty);
  });

  testWidgets('asks once, for the whole word, when the typing stops', (tester) async {
    await tester.pumpWidget(wrap());

    for (final prefix in ['A', 'Ab', 'Abh', 'Abhi']) {
      await tester.enterText(find.byType(TextField), prefix);
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));

    expect(searches, ['Abhi']);
  });

  testWidgets('Enter does not wait', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.byType(TextField), 'Abhi');
    await tester.testTextInput.receiveAction(TextInputAction.search);
    await tester.pump();

    expect(searches, ['Abhi']);
  });

  testWidgets('does not ask twice for the same term', (tester) async {
    // Typing a letter and deleting it again leaves the search where it was.
    await tester.pumpWidget(wrap());

    await tester.enterText(find.byType(TextField), 'Abhi');
    await tester.pump(const Duration(milliseconds: 500));
    await tester.enterText(find.byType(TextField), 'Abhix');
    await tester.enterText(find.byType(TextField), 'Abhi');
    await tester.pump(const Duration(milliseconds: 500));

    expect(searches, ['Abhi']);
  });

  testWidgets('trims what it sends', (tester) async {
    await tester.pumpWidget(wrap());

    await tester.enterText(find.byType(TextField), '  Abhi  ');
    await tester.pump(const Duration(milliseconds: 500));

    expect(searches, ['Abhi']);
  });

  testWidgets('the clear button appears with the first character and empties at once', (tester) async {
    await tester.pumpWidget(wrap());
    expect(find.byTooltip('Clear search'), findsNothing);

    await tester.enterText(find.byType(TextField), 'Abhi');
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byTooltip('Clear search'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear search'));
    await tester.pump();

    // No second wait: clearing is the user saying they have finished.
    expect(searches, ['Abhi', '']);
    expect(controller.text, isEmpty);
    expect(find.byTooltip('Clear search'), findsNothing);
  });

  testWidgets('a pending search dies with the screen', (tester) async {
    // Otherwise the timer fires into a notifier whose screen has gone, from a
    // widget that no longer exists.
    await tester.pumpWidget(wrap());
    await tester.enterText(find.byType(TextField), 'Abhi');

    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await tester.pump(const Duration(milliseconds: 500));

    expect(searches, isEmpty);
  });
}

import 'package:edutrack_app/core/widgets/pagination_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Widget wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  testWidgets('renders nothing when there are no results', (tester) async {
    await tester.pumpWidget(
      wrap(
        PaginationControls(
          currentPage: 1,
          lastPage: 1,
          total: 0,
          perPage: 20,
          onPageChanged: (_) {},
          onPerPageChanged: (_) {},
        ),
      ),
    );

    expect(find.byType(PaginationControls), findsOneWidget);
    expect(find.text('Page 1 of 1'), findsNothing);
  });

  testWidgets('shows the current range and page indicator', (tester) async {
    await tester.pumpWidget(
      wrap(
        PaginationControls(
          currentPage: 2,
          lastPage: 3,
          total: 45,
          perPage: 20,
          onPageChanged: (_) {},
          onPerPageChanged: (_) {},
        ),
      ),
    );

    expect(find.text('Showing 21-40 of 45'), findsOneWidget);
    expect(find.text('Page 2 of 3'), findsOneWidget);
  });

  testWidgets('previous is disabled on the first page, next disabled on the last', (tester) async {
    await tester.pumpWidget(
      wrap(
        PaginationControls(
          currentPage: 1,
          lastPage: 1,
          total: 5,
          perPage: 20,
          onPageChanged: (_) {},
          onPerPageChanged: (_) {},
        ),
      ),
    );

    final prev = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_left));
    final next = tester.widget<IconButton>(find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(prev.onPressed, isNull);
    expect(next.onPressed, isNull);
  });

  testWidgets('tapping next calls onPageChanged with the next page', (tester) async {
    int? changedTo;
    await tester.pumpWidget(
      wrap(
        PaginationControls(
          currentPage: 1,
          lastPage: 3,
          total: 45,
          perPage: 20,
          onPageChanged: (p) => changedTo = p,
          onPerPageChanged: (_) {},
        ),
      ),
    );

    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pump();

    expect(changedTo, 2);
  });

  testWidgets('selecting a different rows-per-page value calls onPerPageChanged', (tester) async {
    int? changedTo;
    await tester.pumpWidget(
      wrap(
        PaginationControls(
          currentPage: 1,
          lastPage: 3,
          total: 45,
          perPage: 20,
          onPageChanged: (_) {},
          onPerPageChanged: (p) => changedTo = p,
        ),
      ),
    );

    await tester.tap(find.byType(DropdownButton<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('50').last);
    await tester.pumpAndSettle();

    expect(changedTo, 50);
  });
}

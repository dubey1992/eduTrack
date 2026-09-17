import 'package:edutrack_app/core/widgets/pagination_controls.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// A desktop window short enough that a full page of rows cannot fit above
/// the pagination bar.
void useShortDesktopWindow(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 700);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// A list page's table must scroll vertically inside the space above its
/// pagination bar. Without that, rows past the bottom are painted straight
/// through the bar - readable on neither - and the last ones can never be
/// reached.
Future<void> expectLastRowScrollsAbovePagination(WidgetTester tester, Finder lastRow) async {
  final verticalScrollable = find.ancestor(
    of: lastRow,
    matching: find.byWidgetPredicate((widget) => widget is Scrollable && widget.axisDirection == AxisDirection.down),
  );
  expect(verticalScrollable, findsWidgets, reason: 'the table does not scroll vertically');

  await tester.scrollUntilVisible(lastRow, 200, scrollable: verticalScrollable.first);
  await tester.pumpAndSettle();

  expect(
    tester.getBottomLeft(lastRow).dy,
    lessThanOrEqualTo(tester.getTopLeft(find.byType(PaginationControls)).dy),
    reason: 'the last row sits under the pagination bar',
  );
}

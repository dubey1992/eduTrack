import 'package:edutrack_app/features/imports/data/models/import_preview.dart';
import 'package:edutrack_app/features/imports/presentation/widgets/import_preview_table.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The step between choosing a file and importing it.
///
/// It exists because "nothing is written unless every row passes" still
/// leaves a file that passes landing unseen, and there is no undo for a
/// hundred records made from the wrong spreadsheet.
ImportPreview preview({int rowCount = 2, bool truncated = false, List<PreviewRow>? rows}) {
  return ImportPreview(
    label: 'Students',
    headings: const ['admission_number', 'first_name'],
    rowCount: rowCount,
    rows:
        rows ??
        const [
          PreviewRow(row: 2, values: ['ADM-1', 'Aarav']),
          PreviewRow(row: 3, values: ['ADM-2', 'Bina']),
        ],
    truncated: truncated,
  );
}

Widget wrap(ImportPreview value) {
  return MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(
      body: SingleChildScrollView(child: ImportPreviewTable(preview: value)),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1200);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('the model', () {
    test('reads the rows and the count from the server', () {
      final parsed = ImportPreview.fromJson({
        'label': 'Class Tests',
        'headings': ['class', 'subject'],
        'row_count': 3,
        'rows': [
          {
            'row': 2,
            'values': ['Grade 8 A', 'Mathematics'],
          },
        ],
        'truncated': true,
      });

      expect(parsed.label, 'Class Tests');
      expect(parsed.rowCount, 3);
      expect(parsed.rows.single.row, 2);
      expect(parsed.rows.single.values, ['Grade 8 A', 'Mathematics']);
      expect(parsed.truncated, isTrue);
    });

    test('an empty answer parses rather than throwing', () {
      final parsed = ImportPreview.fromJson(const {});

      expect(parsed.rowCount, 0);
      expect(parsed.rows, isEmpty);
    });
  });

  group('the table', () {
    testWidgets('shows every column of the file, with its line numbers', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(preview()));
      await tester.pumpAndSettle();

      expect(find.text('admission_number'), findsOneWidget);
      expect(find.text('ADM-1'), findsOneWidget);
      expect(find.text('Bina'), findsOneWidget);
      // The heading is line 1, so the first record is line 2.
      expect(find.text('2'), findsWidgets);
    });

    testWidgets('says how many rows there are and that nothing is saved yet', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(preview()));
      await tester.pumpAndSettle();

      expect(find.text('2 rows in the file.'), findsOneWidget);
      expect(find.textContaining('Nothing has been saved yet'), findsOneWidget);
    });

    testWidgets('a single row reads as one row', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          preview(
            rowCount: 1,
            rows: const [
              PreviewRow(row: 2, values: ['ADM-1', 'Aarav']),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('1 row in the file.'), findsOneWidget);
    });

    testWidgets('a long file says how many it is showing', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(wrap(preview(rowCount: 180, truncated: true)));
      await tester.pumpAndSettle();

      expect(find.text('180 rows in the file. The first 2 are shown.'), findsOneWidget);
    });

    testWidgets('a short row does not break the table', (tester) async {
      useDesktop(tester);

      await tester.pumpWidget(
        wrap(
          preview(
            rows: const [
              PreviewRow(row: 2, values: ['ADM-1']),
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('ADM-1'), findsOneWidget);
    });
  });
}

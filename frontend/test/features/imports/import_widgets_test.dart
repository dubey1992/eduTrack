import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/imports/data/models/import_result.dart';
import 'package:edutrack_app/features/imports/presentation/widgets/import_row_errors.dart';
import 'package:edutrack_app/features/imports/presentation/widgets/import_summary.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// The two halves of what an upload comes back with: the rows to fix, or
/// what landed.
void main() {
  Widget wrap(Widget child) {
    return MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: SizedBox(width: 520, child: child)),
    );
  }

  group('the rows to fix', () {
    testWidgets('names every row and every reason', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ImportRowErrors(
            errors: [
              ImportRowError(row: 3, messages: ['The first name field is required.']),
              ImportRowError(row: 7, messages: ['There is no section "Z" in class "Grade 5".']),
            ],
          ),
        ),
      );

      expect(find.text('Row 3'), findsOneWidget);
      expect(find.text('The first name field is required.'), findsOneWidget);
      expect(find.text('Row 7'), findsOneWidget);
      expect(find.text('There is no section "Z" in class "Grade 5".'), findsOneWidget);
    });

    testWidgets('shows several reasons for one row', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ImportRowErrors(
            errors: [
              ImportRowError(
                row: 4,
                messages: ['The email field must be a valid email address.', 'The role must be one of: HOD, TEACHER.'],
              ),
            ],
          ),
        ),
      );

      expect(find.text('The email field must be a valid email address.'), findsOneWidget);
      expect(find.text('The role must be one of: HOD, TEACHER.'), findsOneWidget);
    });

    testWidgets('a long list scrolls rather than overflowing', (tester) async {
      await tester.pumpWidget(
        wrap(
          ImportRowErrors(
            errors: [
              for (var row = 2; row < 40; row++) ImportRowError(row: row, messages: const ['Something is wrong.']),
            ],
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.byType(ListView), findsOneWidget);
    });
  });

  group('what landed', () {
    testWidgets('says how many, in the words of the thing imported', (tester) async {
      await tester.pumpWidget(wrap(const ImportSummary(result: ImportResult(imported: 12, label: 'Students'))));

      expect(find.text('12 students imported.'), findsOneWidget);
    });

    testWidgets('shows a generated password once, and says so', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ImportSummary(
            result: ImportResult(
              imported: 1,
              label: 'Teachers and Staff',
              created: [
                ImportedRecord(name: 'Priya Nair', email: 'priya@example.com', temporaryPassword: 'Abc#12345678'),
              ],
            ),
          ),
        ),
      );

      expect(find.text('Priya Nair'), findsOneWidget);
      expect(find.text('priya@example.com  -  Abc#12345678'), findsOneWidget);
      expect(find.textContaining('they will be asked to change it when they first sign in'), findsOneWidget);
    });

    testWidgets('says nothing about passwords when none were generated', (tester) async {
      await tester.pumpWidget(
        wrap(
          const ImportSummary(
            result: ImportResult(
              imported: 2,
              label: 'Vehicles',
              created: [ImportedRecord(name: 'Bus 12')],
            ),
          ),
        ),
      );

      expect(find.text('2 vehicles imported.'), findsOneWidget);
      expect(find.textContaining('temporary password'), findsNothing);
    });
  });
}

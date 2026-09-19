import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/status_badge.dart';
import 'package:edutrack_app/features/permissions/data/models/permissions_matrix.dart';
import 'package:edutrack_app/features/permissions/data/permissions_repository.dart';
import 'package:edutrack_app/features/permissions/presentation/permissions_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_permissions_repository.dart';

Widget wrap(FakePermissionsRepository fake) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [permissionsRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: PermissionsScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

Finder cell(String role, String module) => find.byKey(Key('perm-$role-$module'));

PermissionLevel cellLevel(WidgetTester tester, String role, String module) {
  return tester
      .widget<DropdownButton<PermissionLevel>>(
        find.descendant(of: cell(role, module), matching: find.byType(DropdownButton<PermissionLevel>)),
      )
      .value!;
}

/// Opens the cell's dropdown and picks [level].
Future<void> pick(WidgetTester tester, String role, String module, PermissionLevel level) async {
  await tester.tap(find.descendant(of: cell(role, module), matching: find.byType(DropdownButton<PermissionLevel>)));
  await tester.pumpAndSettle();
  await tester.tap(find.text(level.label).last);
  await tester.pumpAndSettle();
}

bool buttonEnabled(WidgetTester tester, Key key) {
  final widget = tester.widget(find.byKey(key));
  return switch (widget) {
    FilledButton() => widget.onPressed != null,
    OutlinedButton() => widget.onPressed != null,
    TextButton() => widget.onPressed != null,
    _ => throw StateError('Not a button: $widget'),
  };
}

/// The matrix as a table the Super Admin edits cell by cell and everybody
/// else reads, with changed cells sent on their own and a confirmation
/// before the defaults are put back.
void main() {
  testWidgets('shows a spinner while the matrix loads', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository()..getGate = Completer<void>();
    await tester.pumpWidget(wrap(fake));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);

    fake.getGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('a failed load shows the error and retries on request', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository(
      failGetWith: const Failure(code: 'FORBIDDEN', message: 'You are not allowed to do this.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('You are not allowed to do this.'), findsOneWidget);
    expect(find.byType(DataTable), findsNothing);

    fake.failGetWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fake.getCalls, 2);
    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('renders the matrix with a row per module and a column per role', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakePermissionsRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Permissions'), findsOneWidget);
    expect(find.textContaining('The matrix decides whether a role may see or change a module'), findsOneWidget);
    expect(find.text('Module'), findsOneWidget);
    expect(find.text('School Admin'), findsOneWidget);
    expect(find.text('HOD'), findsOneWidget);
    expect(find.text('Teacher'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('Student Attendance'), findsOneWidget);
    expect(find.text('Timetable'), findsOneWidget);
    // The description is on hover, not in the row.
    expect(find.byTooltip('The school roll.'), findsOneWidget);

    expect(cellLevel(tester, 'SCHOOL_ADMIN', 'students'), PermissionLevel.manage);
    expect(cellLevel(tester, 'HOD', 'students'), PermissionLevel.none);
    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.view);
    expect(cellLevel(tester, 'TEACHER', 'attendance'), PermissionLevel.manage);

    // At the defaults: nothing to save, nothing to discard, no default tooltips.
    expect(buttonEnabled(tester, const Key('perm-save')), isFalse);
    expect(buttonEnabled(tester, const Key('perm-discard')), isFalse);
    expect(buttonEnabled(tester, const Key('perm-reset')), isTrue);
    expect(find.byTooltip('Default: View'), findsNothing);
    expect(find.text('Only the Super Admin can change the matrix.'), findsNothing);
  });

  testWidgets('a cell that differs from its default is marked with the default', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository(
      matrix: permissionsMatrix(
        matrix: {
          ...permissionDefaults,
          'TEACHER': {...permissionDefaults['TEACHER']!, 'students': PermissionLevel.manage},
        },
      ),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.manage);
    expect(find.byTooltip('Default: View'), findsOneWidget);
    expect(find.descendant(of: cell('TEACHER', 'students'), matching: find.byTooltip('Default: View')), findsOneWidget);
  });

  testWidgets('read-only for everybody but the Super Admin', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakePermissionsRepository(matrix: permissionsMatrix(canEdit: false))));
    await tester.pumpAndSettle();

    expect(find.text('Only the Super Admin can change the matrix.'), findsOneWidget);
    expect(find.byType(DropdownButton<PermissionLevel>), findsNothing);
    expect(find.descendant(of: cell('TEACHER', 'students'), matching: find.byType(StatusBadge)), findsOneWidget);
    expect(find.descendant(of: cell('TEACHER', 'students'), matching: find.text('View')), findsOneWidget);
    expect(find.byKey(const Key('perm-save')), findsNothing);
    expect(find.byKey(const Key('perm-discard')), findsNothing);
    expect(find.byKey(const Key('perm-reset')), findsNothing);
  });

  testWidgets('editing a cell enables Save, and saving sends only the changed cells', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await pick(tester, 'TEACHER', 'students', PermissionLevel.manage);

    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.manage);
    expect(buttonEnabled(tester, const Key('perm-save')), isTrue);
    expect(buttonEnabled(tester, const Key('perm-discard')), isTrue);
    // Marked as off its default before it is even saved.
    expect(find.byTooltip('Default: View'), findsOneWidget);

    await pick(tester, 'HOD', 'attendance', PermissionLevel.view);
    await tester.tap(find.byKey(const Key('perm-save')));
    await tester.pumpAndSettle();

    expect(fake.saveCalls, 1);
    expect(fake.lastSave, {
      'TEACHER': {'students': 'manage'},
      'HOD': {'attendance': 'view'},
    });
    expect(find.text('Permissions saved.'), findsOneWidget);
    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.manage);
    expect(cellLevel(tester, 'HOD', 'attendance'), PermissionLevel.view);
    // Saved: nothing left to send.
    expect(buttonEnabled(tester, const Key('perm-save')), isFalse);
    expect(buttonEnabled(tester, const Key('perm-discard')), isFalse);
  });

  testWidgets('a cell put back to what the server has is not a change', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await pick(tester, 'TEACHER', 'students', PermissionLevel.manage);
    expect(buttonEnabled(tester, const Key('perm-save')), isTrue);

    await pick(tester, 'TEACHER', 'students', PermissionLevel.view);
    expect(buttonEnabled(tester, const Key('perm-save')), isFalse);
    expect(buttonEnabled(tester, const Key('perm-discard')), isFalse);
  });

  testWidgets('discard puts the edited cells back', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await pick(tester, 'TEACHER', 'students', PermissionLevel.manage);
    await pick(tester, 'HOD', 'timetable', PermissionLevel.none);
    await tester.tap(find.byKey(const Key('perm-discard')));
    await tester.pumpAndSettle();

    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.view);
    expect(cellLevel(tester, 'HOD', 'timetable'), PermissionLevel.view);
    expect(buttonEnabled(tester, const Key('perm-save')), isFalse);
    expect(fake.saveCalls, 0);
  });

  testWidgets('reset asks first, then puts the defaults back', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository(
      matrix: permissionsMatrix(
        matrix: {
          ...permissionDefaults,
          'TEACHER': {...permissionDefaults['TEACHER']!, 'students': PermissionLevel.manage},
        },
      ),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.manage);

    await tester.tap(find.byKey(const Key('perm-reset')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Reset to defaults?'), findsOneWidget);
    expect(fake.resetCalls, 0);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();
    expect(fake.resetCalls, 0);
    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.manage);

    await tester.tap(find.byKey(const Key('perm-reset')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Reset'));
    await tester.pumpAndSettle();

    expect(fake.resetCalls, 1);
    expect(find.byType(AlertDialog), findsNothing);
    expect(find.text('Permissions reset to defaults.'), findsOneWidget);
    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.view);
    expect(find.byTooltip('Default: View'), findsNothing);
  });

  testWidgets('a save the server refuses shows its sentence and keeps the edits', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository(
      failSaveWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'HOD Reports cannot be set to manage for a Teacher.',
        details: {
          'errors': {
            'matrix': ['HOD Reports cannot be set to manage for a Teacher.'],
          },
        },
      ),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await pick(tester, 'TEACHER', 'students', PermissionLevel.manage);
    await tester.tap(find.byKey(const Key('perm-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('perm-error')), findsOneWidget);
    expect(find.text('HOD Reports cannot be set to manage for a Teacher.'), findsOneWidget);
    expect(find.text('Permissions saved.'), findsNothing);
    // The edit is still on screen to be corrected or discarded.
    expect(cellLevel(tester, 'TEACHER', 'students'), PermissionLevel.manage);
    expect(buttonEnabled(tester, const Key('perm-save')), isTrue);
  });

  testWidgets('a save the server forbids shows its reason', (tester) async {
    useDesktop(tester);
    final fake = FakePermissionsRepository(
      failSaveWith: const Failure(code: 'FORBIDDEN', message: 'Only the Super Admin can change the matrix.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await pick(tester, 'TEACHER', 'students', PermissionLevel.manage);
    await tester.tap(find.byKey(const Key('perm-save')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('perm-error')), findsOneWidget);
    expect(find.text('Only the Super Admin can change the matrix.'), findsOneWidget);
    expect(find.byType(DataTable), findsOneWidget);
  });

  testWidgets('fits a phone: the table scrolls sideways and nothing overflows', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(FakePermissionsRepository()));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DataTable), findsOneWidget);
    expect(cell('SCHOOL_ADMIN', 'students'), findsOneWidget);
  });
}

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/staff/presentation/add_staff_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_staff_repository.dart';

// A SCHOOL_ADMIN actor is used throughout so the dialog never renders its
// school picker (that's SUPER_ADMIN-only, see AddStaffDialog._SchoolPicker)
// - keeping these tests focused on the validation/submit behavior that's
// common to every actor.
const _schoolAdmin = AuthenticatedUser(id: 5, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeStaffRepository fake) {
  return ProviderScope(
    overrides: [
      staffRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _schoolAdmin)),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository()),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const AddStaffDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _openDialog(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

Future<void> _fillRequiredFields(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'First name'), 'Ananya');
  await tester.enterText(find.widgetWithText(TextFormField, 'Last name'), 'Rao');
  await tester.enterText(find.widgetWithText(TextFormField, 'Employee ID'), 'STF-100');
  await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'ananya.rao@example.com');
  await tester.enterText(find.widgetWithText(TextFormField, 'Password'), 'password123');
}

void main() {
  testWidgets('shows validation errors when required fields are missing', (tester) async {
    await tester.pumpWidget(wrap(FakeStaffRepository()));
    await _openDialog(tester);

    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    // First name, last name and employee ID all share the same "Required"
    // validator message.
    expect(find.text('Required'), findsNWidgets(3));
    expect(find.text('Enter a valid email'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
  });

  testWidgets('creates the employee, closes the dialog, and shows a confirmation snackbar', (tester) async {
    final fake = FakeStaffRepository();
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await _fillRequiredFields(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    final created = await fake.list();
    expect(created, hasLength(1));
    expect(created.single.employeeId, 'STF-100');
    expect(created.single.email, 'ananya.rao@example.com');
    expect(find.byType(AddStaffDialog), findsNothing);
    expect(find.text('Employee added.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open when the repository throws', (tester) async {
    final fake = FakeStaffRepository(
      failCreateWith: const Failure(code: 'STAFF_CREATE_FAILED', message: 'Could not add the employee.'),
    );
    await tester.pumpWidget(wrap(fake));
    await _openDialog(tester);

    await _fillRequiredFields(tester);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();

    expect(find.text('Could not add the employee.'), findsOneWidget);
    expect(find.byType(AddStaffDialog), findsOneWidget);
  });
}

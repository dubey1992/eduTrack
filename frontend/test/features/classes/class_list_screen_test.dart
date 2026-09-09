import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/classes/presentation/add_section_dialog.dart';
import 'package:edutrack_app/features/classes/presentation/class_list_screen.dart';
import 'package:edutrack_app/features/classes/presentation/edit_class_dialog.dart';
import 'package:edutrack_app/features/classes/presentation/edit_section_dialog.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_user_repository.dart';

const _classTeacher = AppUser(
  id: 9,
  firstName: 'Priya',
  lastName: 'Sharma',
  name: 'Priya Sharma',
  email: 'priya.sharma@example.com',
  mobile: null,
  role: UserRole.teacher,
  status: UserStatus.active,
);

const _section = ClassSection(
  id: 1,
  schoolClassId: 1,
  name: 'A',
  roomNumber: 'Room 204',
  classTeacherId: 9,
  classTeacherName: 'Priya Sharma',
);

const _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 3,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: [_section],
);

Widget wrap(FakeSchoolClassRepository fake) {
  return ProviderScope(
    overrides: [
      schoolClassRepositoryProvider.overrideWithValue(fake),
      userRepositoryProvider.overrideWithValue(FakeUserRepository(users: const [_classTeacher])),
      authRepositoryProvider.overrideWithValue(
        FakeAuthRepository(
          sessionOnRestore: const AuthenticatedUser(
            id: 1,
            name: 'Admin',
            email: 'admin@example.com',
            role: UserRole.superAdmin,
          ),
        ),
      ),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: ClassListScreen()),
    ),
  );
}

void main() {
  testWidgets('shows an empty state when there are no classes', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No classes set up yet.'), findsOneWidget);
  });

  testWidgets('shows a class card with its section', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository(classes: [_schoolClass])));
    await tester.pumpAndSettle();

    expect(find.text('Grade 8'), findsOneWidget);
    expect(find.text('Section A'), findsOneWidget);
    expect(find.textContaining('Priya Sharma'), findsOneWidget);
  });

  testWidgets('tapping the edit class action opens the edit dialog for that class', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository(classes: [_schoolClass])));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit class'));
    await tester.pumpAndSettle();

    expect(find.byType(EditClassDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Grade / Class (e.g. Grade 8)'), findsOneWidget);
  });

  testWidgets('confirming the delete class action removes the class and shows confirmation', (tester) async {
    final fake = FakeSchoolClassRepository(classes: [_schoolClass]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete class'));
    await tester.pumpAndSettle();

    expect(find.text('Delete class?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await fake.list(), isEmpty);
    expect(find.text('No classes set up yet.'), findsOneWidget);
    expect(find.text('Grade 8 was deleted.'), findsOneWidget);
  });

  testWidgets('tapping the edit section action opens the edit dialog for that section', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository(classes: [_schoolClass])));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Edit section'));
    await tester.pumpAndSettle();

    expect(find.byType(EditSectionDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Section (e.g. A)'), findsOneWidget);
  });

  testWidgets('confirming the delete section action removes only that section', (tester) async {
    final fake = FakeSchoolClassRepository(classes: [_schoolClass]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Delete section'));
    await tester.pumpAndSettle();

    expect(find.text('Delete section?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    final classes = await fake.list();
    expect(classes.single.sections, isEmpty);
    expect(find.text('Grade 8'), findsOneWidget);
    expect(find.text('No sections yet.'), findsOneWidget);
    expect(find.text('Section A was deleted.'), findsOneWidget);
  });

  testWidgets('tapping Add Section opens the add-section dialog for that class', (tester) async {
    await tester.pumpWidget(wrap(FakeSchoolClassRepository(classes: [_schoolClass])));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'Add Section'));
    await tester.pumpAndSettle();

    expect(find.byType(AddSectionDialog), findsOneWidget);
    expect(find.text('Add Section to Grade 8'), findsOneWidget);
  });

  testWidgets('shows the error state with a retry button when loading fails', (tester) async {
    final fake = FakeSchoolClassRepository(
      failListPageWith: const Failure(code: 'SERVER_ERROR', message: 'Could not load classes.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load classes.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);

    fake.failListPageWith = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No classes set up yet.'), findsOneWidget);
  });
}

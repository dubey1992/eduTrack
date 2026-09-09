import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/subjects/data/models/subject.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/subjects/presentation/edit_subject_dialog.dart';
import 'package:edutrack_app/features/subjects/presentation/subject_list_screen.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:edutrack_app/features/users/data/user_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_subject_repository.dart';
import '../../support/fake_user_repository.dart';

const _department = Department(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: null,
  hodName: null,
);

const _leadTeacher = AppUser(
  id: 9,
  firstName: 'Priya',
  lastName: 'Sharma',
  name: 'Priya Sharma',
  email: 'priya.sharma@example.com',
  mobile: null,
  role: UserRole.teacher,
  status: UserStatus.active,
);

const _subject = Subject(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: 2,
  departmentName: 'Mathematics',
  code: 'MAT',
  name: 'Mathematics',
  minClassLevel: 7,
  maxClassLevel: 10,
  leadTeacherId: 9,
  leadTeacherName: 'Priya Sharma',
);

Widget wrap(FakeSubjectRepository fake) {
  return ProviderScope(
    overrides: [
      subjectRepositoryProvider.overrideWithValue(fake),
      departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository(departments: const [_department])),
      userRepositoryProvider.overrideWithValue(FakeUserRepository(users: const [_leadTeacher])),
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
      home: const Scaffold(body: SubjectListScreen()),
    ),
  );
}

void main() {
  testWidgets('shows an empty state when there are no subjects', (tester) async {
    await tester.pumpWidget(wrap(FakeSubjectRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No subjects set up yet.'), findsOneWidget);
  });

  testWidgets('shows a subject row with its department and lead teacher', (tester) async {
    await tester.pumpWidget(wrap(FakeSubjectRepository(subjects: [_subject])));
    await tester.pumpAndSettle();

    expect(find.textContaining('MAT'), findsOneWidget);
    expect(find.textContaining('Priya Sharma'), findsOneWidget);
  });

  testWidgets('tapping the edit action opens the edit dialog for that row', (tester) async {
    await tester.pumpWidget(wrap(FakeSubjectRepository(subjects: [_subject])));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();

    expect(find.byType(EditSubjectDialog), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Code (e.g. MAT)'), findsOneWidget);
  });

  testWidgets('confirming the delete action removes the row and shows confirmation', (tester) async {
    final fake = FakeSubjectRepository(subjects: [_subject]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();

    expect(find.text('Delete subject?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();

    expect(await fake.list(), isEmpty);
    expect(find.text('No subjects set up yet.'), findsOneWidget);
    expect(find.text('Mathematics was deleted.'), findsOneWidget);
  });

  testWidgets('cancelling the delete confirmation leaves the row untouched', (tester) async {
    final fake = FakeSubjectRepository(subjects: [_subject]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byIcon(Icons.delete_outline));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(await fake.list(), hasLength(1));
    expect(find.textContaining('MAT'), findsOneWidget);
  });

  testWidgets('shows the error state with a retry button when loading fails', (tester) async {
    final fake = FakeSubjectRepository(
      failListPageWith: const Failure(code: 'SERVER_ERROR', message: 'Could not load subjects.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Could not load subjects.'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);

    fake.failListPageWith = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('No subjects set up yet.'), findsOneWidget);
  });
}

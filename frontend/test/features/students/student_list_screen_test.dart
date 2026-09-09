import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/presentation/student_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_student_repository.dart';

final _student = Student(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: 1,
  classSectionName: 'Grade 8 A',
  admissionNumber: 'STU-0042',
  firstName: 'Arjun',
  lastName: 'Kumar',
  name: 'Arjun Kumar',
  rollNumber: '12',
  guardianName: 'Raj Kumar',
  guardianMobile: '9876543210',
  address: null,
  status: StudentStatus.active,
);

Widget wrap(FakeStudentRepository fake) {
  return ProviderScope(
    overrides: [
      studentRepositoryProvider.overrideWithValue(fake),
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
      home: const Scaffold(body: StudentListScreen()),
    ),
  );
}

void main() {
  testWidgets('shows an empty state when there are no students', (tester) async {
    await tester.pumpWidget(wrap(FakeStudentRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No students admitted yet.'), findsOneWidget);
  });

  testWidgets('shows a student with their class and guardian', (tester) async {
    await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student])));
    await tester.pumpAndSettle();

    expect(find.textContaining('STU-0042'), findsOneWidget);
    expect(find.textContaining('Arjun Kumar'), findsOneWidget);
  });

  testWidgets('filtering by search hides non-matching students', (tester) async {
    final other = Student(
      id: 2,
      schoolId: 1,
      schoolName: 'Sunrise Public School',
      classSectionId: 1,
      classSectionName: 'Grade 8 A',
      admissionNumber: 'STU-0043',
      firstName: 'Aarav',
      lastName: 'Mehta',
      name: 'Aarav Mehta',
      rollNumber: '13',
      guardianName: 'Neha Mehta',
      guardianMobile: null,
      address: null,
      status: StudentStatus.active,
    );
    await tester.pumpWidget(wrap(FakeStudentRepository(students: [_student, other])));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Search by name / admission ID'), 'Arjun');
    await tester.pumpAndSettle();

    expect(find.textContaining('Arjun Kumar'), findsOneWidget);
    expect(find.textContaining('Aarav Mehta'), findsNothing);
  });
}

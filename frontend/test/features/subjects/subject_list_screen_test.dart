import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/subjects/data/models/subject.dart';
import 'package:edutrack_app/features/subjects/data/subject_repository.dart';
import 'package:edutrack_app/features/subjects/presentation/subject_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_subject_repository.dart';

Widget wrap(FakeSubjectRepository fake) {
  return ProviderScope(
    overrides: [
      subjectRepositoryProvider.overrideWithValue(fake),
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
    await tester.pumpWidget(
      wrap(
        FakeSubjectRepository(
          subjects: [
            const Subject(
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
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('MAT'), findsOneWidget);
    expect(find.textContaining('Priya Sharma'), findsOneWidget);
  });
}

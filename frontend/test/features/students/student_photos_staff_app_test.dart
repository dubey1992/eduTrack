import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/photo_picker.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:edutrack_app/core/widgets/user_avatar.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_register.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_register/data/models/saved_register.dart';
import 'package:edutrack_app/features/my_register/data/register_store.dart';
import 'package:edutrack_app/features/my_register/presentation/register_screen.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/presentation/student_lookup_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_attendance_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_photo_dio.dart';
import '../../support/fake_student_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';
import '../my_register/register_fixtures.dart';

/// Student photos in the staff app (docs/student-photos.md, P3): beside each
/// name in the register (D4), and in Find a student, where a class teacher
/// sets their own section's photos (D3).

void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 860);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

UserAvatar _avatarIn(WidgetTester tester, Finder row) =>
    tester.widget<UserAvatar>(find.descendant(of: row, matching: find.byType(UserAvatar)));

void main() {
  group('the register', () {
    Future<void> pump(WidgetTester tester, FakeAttendanceRepository attendance, InMemoryKeyValueStore store) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [...registerOverrides(attendance, store), dioClientProvider.overrideWithValue(fakePhotoDio())],
          child: MaterialApp(
            theme: AppTheme.teacherLight(),
            home: const RegisterScreen(registerKey: (sectionId: sectionId, date: day, label: 'Grade 3 A')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('each row shows the student photo, or the initials', (tester) async {
      final attendance = FakeAttendanceRepository(register: registerOf(photos: const {1: '/students/1/photo?v=a1'}));
      await pump(tester, attendance, InMemoryKeyValueStore());

      expect(_avatarIn(tester, find.byKey(const Key('register-row-1'))).photoUrl, '/students/1/photo?v=a1');
      expect(_avatarIn(tester, find.byKey(const Key('register-row-2'))).photoUrl, isNull);
      // The photo cannot be fetched here, so the initials stand in.
      expect(find.text('DP'), findsOneWidget);
    });

    testWidgets("a register opened from the phone's copy, with no signal, shows the initials", (tester) async {
      final store = InMemoryKeyValueStore();
      await RegisterStore(store)
          .saveRoster(sectionId, const [CachedStudent(studentId: 1, name: 'Aarav Shah', rollNumber: '1')]);
      final attendance = FakeAttendanceRepository(register: registerOf())..failRegisterWith = Failure.network();
      await pump(tester, attendance, store);

      expect(_avatarIn(tester, find.byKey(const Key('register-row-1'))).photoUrl, isNull);
      expect(find.text('AS'), findsOneWidget);
    });

    test('the photo address is read from the server', () {
      final entry = AttendanceRosterEntry.fromJson(const {
        'student_id': 1,
        'name': 'Aarav Shah',
        'roll_number': '1',
        'status': null,
        'remarks': null,
        'absence_note': null,
        'photo_url': '/students/1/photo?v=a1',
      });

      expect(entry.photoUrl, '/students/1/photo?v=a1');
      expect(entry.copyWith(remarks: 'late').photoUrl, '/students/1/photo?v=a1');
    });
  });

  group('Find a student', () {
    Student student({String? photoUrl}) => Student(
      id: 1,
      schoolId: 1,
      schoolName: 'Sunrise Public School',
      classSectionId: 5,
      classSectionName: 'Grade 8 A',
      admissionNumber: 'ADM-1',
      firstName: 'Aarav',
      lastName: 'Rao',
      name: 'Aarav Rao',
      rollNumber: '1',
      guardianName: 'Meera Rao',
      guardianMobile: null,
      address: null,
      status: StudentStatus.active,
      photoUrl: photoUrl,
    );

    Future<void> pump(WidgetTester tester, FakeStudentRepository repository, UserRole role) async {
      _phone(tester);
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            studentRepositoryProvider.overrideWithValue(repository),
            dioClientProvider.overrideWithValue(fakePhotoDio()),
            authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: sessionUser(role))),
            photoPickerProvider.overrideWithValue(
              (source) async => PickedFile(name: 'aarav.jpg', bytes: List.filled(100, 1)),
            ),
          ],
          child: MaterialApp(theme: AppTheme.teacherLight(), home: const StudentLookupScreen()),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('each student shows their photo', (tester) async {
      await pump(
        tester,
        FakeStudentRepository(students: [student(photoUrl: '/students/1/photo?v=1')]),
        UserRole.teacher,
      );

      expect(_avatarIn(tester, find.byKey(const Key('student-lookup-1'))).photoUrl, '/students/1/photo?v=1');
    });

    testWidgets("a class teacher sets a student's photo from here, and the list shows it", (tester) async {
      final repository = FakeStudentRepository(students: [student()]);
      await pump(tester, repository, UserRole.teacher);

      await tester.tap(find.byKey(const Key('student-lookup-photo-1')));
      await tester.pumpAndSettle();
      expect(find.text("Aarav Rao's photo"), findsOneWidget);

      await tester.tap(find.byKey(const Key('student-photo-upload')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('student-photo-camera')));
      await tester.pumpAndSettle();

      expect(repository.calls, contains('uploadPhoto'));
      expect(find.text('Photo saved.'), findsOneWidget);

      // Close the sheet: the list behind has been asked again and carries it.
      await tester.tapAt(const Offset(200, 40));
      await tester.pumpAndSettle();
      expect(_avatarIn(tester, find.byKey(const Key('student-lookup-1'))).photoUrl, '/students/1/photo?v=1');
    });

    testWidgets('an admin is offered it too', (tester) async {
      await pump(tester, FakeStudentRepository(students: [student()]), UserRole.schoolAdmin);

      expect(find.byKey(const Key('student-lookup-photo-1')), findsOneWidget);
    });

    for (final role in [UserRole.accountant, UserRole.staff, UserRole.hod]) {
      testWidgets('${role.label} is not offered it', (tester) async {
        await pump(tester, FakeStudentRepository(students: [student()]), role);

        expect(find.byKey(const Key('student-lookup-photo-1')), findsNothing);
      });
    }
  });
}

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/dio_client.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/photo_picker.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:edutrack_app/core/widgets/user_avatar.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/students/presentation/edit_student_dialog.dart';
import 'package:edutrack_app/features/students/presentation/student_list_screen.dart';
import 'package:edutrack_app/features/transport/data/transport_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_photo_dio.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_student_repository.dart';
import '../../support/fake_transport_repository.dart';

/// A student's photo (docs/student-photos.md, P1): what the app reads from
/// the server, the photo in the Students list, and adding, refusing and
/// removing one from the Edit Student dialog.

final _schoolClass = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(id: 1, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
  ],
);

Student _arjun({String? photoUrl}) => Student(
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
  photoUrl: photoUrl,
);

List<Override> _overrides(FakeStudentRepository fake, {PhotoPicker? picker}) => [
  studentRepositoryProvider.overrideWithValue(fake),
  transportRepositoryProvider.overrideWithValue(FakeTransportRepository()),
  schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_schoolClass])),
  // Photos are fetched through the app's Dio; here every fetch is a 404,
  // so the initials stand in - what the tests look at is the address.
  dioClientProvider.overrideWithValue(fakePhotoDio()),
  authRepositoryProvider.overrideWithValue(
    FakeAuthRepository(
      sessionOnRestore: const AuthenticatedUser(
        id: 1,
        name: 'Admin',
        email: 'admin@example.com',
        role: UserRole.schoolAdmin,
        schoolId: 1,
      ),
    ),
  ),
  if (picker != null) photoPickerProvider.overrideWithValue(picker),
];

Widget _dialogApp(FakeStudentRepository fake, {PhotoPicker? picker}) {
  return ProviderScope(
    overrides: _overrides(fake, picker: picker),
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(
              context: context,
              builder: (_) => EditStudentDialog(student: fake.students.first),
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester) async {
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// Taps "Add photo" or "Change photo" and picks from the phone's photos -
/// tests run as a phone, so the camera-or-photos sheet is asked first.
Future<void> _pickFromPhotos(WidgetTester tester) async {
  await tester.tap(find.byKey(const Key('student-photo-upload')));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const Key('student-photo-gallery')));
  await tester.pumpAndSettle();
}

PhotoPicker _gives(PickedFile file) =>
    (source) async => file;

void _useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('what the server sends', () {
    Map<String, dynamic> json({Object? photoUrl}) => {
      'id': 1,
      'school_id': 1,
      'admission_number': 'STU-0042',
      'first_name': 'Arjun',
      'last_name': 'Kumar',
      'name': 'Arjun Kumar',
      'guardian_name': 'Raj Kumar',
      'status': 'active',
      'photo_url': photoUrl,
    };

    test('a photo address is kept, and no photo is null', () {
      expect(Student.fromJson(json(photoUrl: '/students/1/photo?v=ab12')).photoUrl, '/students/1/photo?v=ab12');
      expect(Student.fromJson(json()).photoUrl, isNull);
    });

    test('a copy keeps the photo unless it is replaced or cleared', () {
      final student = _arjun(photoUrl: '/students/1/photo?v=1');

      expect(student.copyWith(status: StudentStatus.inactive).photoUrl, '/students/1/photo?v=1');
      expect(student.copyWith(photoUrl: '/students/1/photo?v=2').photoUrl, '/students/1/photo?v=2');
      expect(student.copyWith(clearPhoto: true).photoUrl, isNull);
    });
  });

  group('the Students list', () {
    UserAvatar avatarIn(WidgetTester tester) => tester.widget<UserAvatar>(find.byType(UserAvatar).first);

    testWidgets('each row shows the student photo on the desktop', (tester) async {
      _useDesktop(tester);
      final fake = FakeStudentRepository(students: [_arjun(photoUrl: '/students/1/photo?v=1')]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(fake),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: StudentListScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(avatarIn(tester).photoUrl, '/students/1/photo?v=1');
      expect(avatarIn(tester).name, 'Arjun Kumar');
    });

    testWidgets('a student with no photo shows their initials on a phone', (tester) async {
      final fake = FakeStudentRepository(students: [_arjun()]);
      await tester.pumpWidget(
        ProviderScope(
          overrides: _overrides(fake),
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: StudentListScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(avatarIn(tester).photoUrl, isNull);
      expect(find.text('AK'), findsOneWidget);
    });
  });

  group('the Edit Student dialog', () {
    testWidgets('a student with no photo can have one added, and it saves at once', (tester) async {
      final fake = FakeStudentRepository(students: [_arjun()]);
      await tester.pumpWidget(
        _dialogApp(
          fake,
          picker: _gives(PickedFile(name: 'arjun.jpg', bytes: List.filled(1000, 1))),
        ),
      );
      await _open(tester);

      expect(find.text('Add photo'), findsOneWidget);
      expect(find.byKey(const Key('student-photo-remove')), findsNothing);

      await _pickFromPhotos(tester);

      expect(fake.calls, contains('uploadPhoto'));
      expect(find.text('Photo saved.'), findsOneWidget);
      expect(find.text('Change photo'), findsOneWidget);
      expect(find.byKey(const Key('student-photo-remove')), findsOneWidget);
      expect(fake.students.first.photoUrl, '/students/1/photo?v=1');
    });

    testWidgets('on a phone the photo can come from the camera', (tester) async {
      final asked = <PhotoSource>[];
      final fake = FakeStudentRepository(students: [_arjun()]);
      await tester.pumpWidget(
        _dialogApp(
          fake,
          picker: (source) async {
            asked.add(source);
            return PickedFile(name: 'arjun.png', bytes: List.filled(10, 1));
          },
        ),
      );
      await _open(tester);

      await tester.tap(find.byKey(const Key('student-photo-upload')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('student-photo-camera')));
      await tester.pumpAndSettle();

      expect(asked, [PhotoSource.camera]);
      expect(fake.calls, contains('uploadPhoto'));
    });

    testWidgets('a file that is not a JPEG or PNG is refused before it is sent', (tester) async {
      final fake = FakeStudentRepository(students: [_arjun()]);
      await tester.pumpWidget(
        _dialogApp(
          fake,
          picker: _gives(const PickedFile(name: 'arjun.heic', bytes: [1, 2])),
        ),
      );
      await _open(tester);

      await _pickFromPhotos(tester);

      expect(find.text('The photo must be a JPEG or PNG image.'), findsOneWidget);
      expect(fake.calls, isNot(contains('uploadPhoto')));
    });

    testWidgets('a photo over 5 MB is refused before it is sent', (tester) async {
      final fake = FakeStudentRepository(students: [_arjun()]);
      await tester.pumpWidget(
        _dialogApp(
          fake,
          picker: _gives(PickedFile(name: 'big.jpg', bytes: List.filled(5 * 1024 * 1024 + 1, 1))),
        ),
      );
      await _open(tester);

      await _pickFromPhotos(tester);

      expect(find.text('The photo must be 5 MB or smaller.'), findsOneWidget);
      expect(fake.calls, isNot(contains('uploadPhoto')));
    });

    testWidgets("the server's refusal is shown under the photo", (tester) async {
      final fake = FakeStudentRepository(
        students: [_arjun()],
        failWith: {
          'uploadPhoto': const Failure(
            code: 'VALIDATION_ERROR',
            message: 'The given data was invalid.',
            details: {
              'errors': {
                'photo': ['The photo must be a JPEG or PNG image.'],
              },
            },
          ),
        },
      );
      await tester.pumpWidget(
        _dialogApp(
          fake,
          picker: _gives(PickedFile(name: 'fake.jpg', bytes: List.filled(10, 1))),
        ),
      );
      await _open(tester);

      await _pickFromPhotos(tester);

      expect(find.byKey(const Key('student-photo-error')), findsOneWidget);
      expect(find.text('The photo must be a JPEG or PNG image.'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
    });

    testWidgets('choosing nothing changes nothing', (tester) async {
      final fake = FakeStudentRepository(students: [_arjun()]);
      await tester.pumpWidget(_dialogApp(fake, picker: (source) async => null));
      await _open(tester);

      await _pickFromPhotos(tester);

      expect(fake.calls, isNot(contains('uploadPhoto')));
      expect(find.byKey(const Key('student-photo-error')), findsNothing);
    });

    testWidgets('a photo is removed only after asking', (tester) async {
      final fake = FakeStudentRepository(students: [_arjun(photoUrl: '/students/1/photo?v=1')]);
      await tester.pumpWidget(_dialogApp(fake));
      await _open(tester);

      await tester.tap(find.byKey(const Key('student-photo-remove')));
      await tester.pumpAndSettle();
      expect(find.text('Remove photo?'), findsOneWidget);
      expect(find.text("Arjun Kumar's initials will be shown instead."), findsOneWidget);

      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();

      expect(fake.calls, contains('removePhoto'));
      expect(find.text('Photo removed.'), findsOneWidget);
      expect(find.text('Add photo'), findsOneWidget);
      expect(fake.students.first.photoUrl, isNull);
    });

    testWidgets('cancelling the question keeps the photo', (tester) async {
      final fake = FakeStudentRepository(students: [_arjun(photoUrl: '/students/1/photo?v=1')]);
      await tester.pumpWidget(_dialogApp(fake));
      await _open(tester);

      await tester.tap(find.byKey(const Key('student-photo-remove')));
      await tester.pumpAndSettle();
      // The Edit Student dialog has its own Cancel; the question's is on top.
      await tester.tap(find.text('Cancel').last);
      await tester.pumpAndSettle();

      expect(fake.calls, isNot(contains('removePhoto')));
      expect(fake.students.first.photoUrl, '/students/1/photo?v=1');
    });
  });
}

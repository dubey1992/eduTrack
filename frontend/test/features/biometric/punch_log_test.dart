import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/utils/picked_file.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/biometric/data/biometric_repository.dart';
import 'package:edutrack_app/features/biometric/data/models/biometric_punch.dart';
import 'package:edutrack_app/features/biometric/presentation/device_list_screen.dart';
import 'package:edutrack_app/features/biometric/presentation/punch_upload_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_biometric_repository.dart';
import '../../support/fake_school_repository.dart';

/// What the devices recorded (docs/biometric.md, B2).
///
/// The log earns its place by naming the punches nobody can attribute. A
/// blank in the Who column would read as "no information"; it is in fact
/// somebody's next job, so these tests hold the screen to saying so - both
/// on the row and in the count above the list, which the page itself cannot
/// know.
const _admin = AuthenticatedUser(id: 1, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeBiometricRepository fake, {AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    overrides: [
      biometricRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: DeviceListScreen()),
    ),
  );
}

const _branchSchool = School(
  id: 7,
  name: 'Map Demo Delhi Branch',
  registrationNumber: null,
  email: 'delhi@example.com',
  phone: '+91 98765 43210',
  address: '12 School Road',
  city: 'New Delhi',
  state: 'Delhi',
  country: 'India',
  postalCode: '110001',
  currencyCode: 'INR',
  timezone: 'UTC',
  logoUrl: null,
  status: SchoolStatus.active,
);

/// The upload dialog on its own, worn by whichever actor the test needs.
Widget wrapDialog(FakeBiometricRepository fake, {AuthenticatedUser actor = _admin, int? schoolId}) {
  return ProviderScope(
    overrides: [
      biometricRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: const [_branchSchool])),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: PunchUploadDialog(pick: fakePicker, schoolId: schoolId),
      ),
    ),
  );
}

/// Stands in for the browser's own file dialog.
Future<PickedFile?> fakePicker({required String accept}) async {
  return const PickedFile(name: 'punches.csv', bytes: [1, 2, 3]);
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// The screen opens on the devices; the log is the other half of the toggle.
Future<void> openTheLog(WidgetTester tester) async {
  await tester.pumpAndSettle();
  await tester.tap(find.text('Punch log'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the screen opens on the devices, not the log', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [fakeDevice()])));
    await tester.pumpAndSettle();

    expect(find.text('Front gate'), findsOneWidget);
    expect(find.text('Search the log'), findsNothing);
  });

  testWidgets('the toggle swaps the devices for what they recorded', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [fakeDevice()], punches: [fakePunch()])));
    await openTheLog(tester);

    expect(find.text('ZK-0001'), findsNothing);
    expect(find.text('Ada Ogun'), findsOneWidget);
    expect(find.text('10/20/2026 09:02 AM'), findsOneWidget);
    expect(find.text('EMP-004'), findsOneWidget);
  });

  testWidgets('no punches yet says so', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeBiometricRepository()));
    await openTheLog(tester);

    expect(find.text('No punches recorded yet.'), findsOneWidget);
  });

  testWidgets('a failure shows its message with a retry', (tester) async {
    useDesktop(tester);
    final fake = FakeBiometricRepository()..failPunchesWith = Failure.network();
    await tester.pumpWidget(wrap(fake));
    await openTheLog(tester);

    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
  });

  group('punches nobody has been mapped to', () {
    testWidgets('the row names the device id instead of leaving a blank', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          FakeBiometricRepository(
            punches: [fakePunch(staffProfileId: null, staffName: null, employeeId: null, biometricUserId: '42')],
            unmatchedTotal: 1,
          ),
        ),
      );
      await openTheLog(tester);

      expect(find.text('Nobody mapped to 42'), findsOneWidget);
    });

    testWidgets('one of them is counted above the list, in the singular', (tester) async {
      // The count comes from the server under the same filters: a page of
      // twenty cannot tell "none here" from "none at all".
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(punches: [fakePunch()], unmatchedTotal: 1)));
      await openTheLog(tester);

      expect(find.textContaining('1 punch belongs to a device ID'), findsOneWidget);
    });

    testWidgets('several are counted in the plural', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(punches: [fakePunch()], unmatchedTotal: 7)));
      await openTheLog(tester);

      expect(find.textContaining('7 punches belong to device IDs'), findsOneWidget);
    });

    testWidgets('none of them says nothing at all', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(punches: [fakePunch()])));
      await openTheLog(tester);

      expect(find.textContaining('nobody has been mapped to'), findsNothing);
    });

    testWidgets('the chip asks the server for only those', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository(
        punches: [
          fakePunch(),
          fakePunch(id: 2, staffProfileId: null, staffName: null, biometricUserId: '42'),
        ],
        unmatchedTotal: 1,
      );
      await tester.pumpWidget(wrap(fake));
      await openTheLog(tester);

      await tester.tap(find.byKey(const Key('unattributed-only')));
      await tester.pumpAndSettle();

      expect(fake.lastUnmatchedOnly, isTrue);
      expect(find.text('Ada Ogun'), findsNothing);
      expect(find.text('Nobody mapped to 42'), findsOneWidget);
    });
  });

  testWidgets('an uploaded punch names no device', (tester) async {
    // A file says who and when, not which reader they used, and "Uploaded"
    // is the honest answer rather than a dash that reads as missing data.
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeBiometricRepository(punches: [fakePunch(deviceName: null, source: 'upload')])));
    await openTheLog(tester);

    expect(find.text('Uploaded'), findsOneWidget);
  });

  testWidgets('searching asks the server', (tester) async {
    useDesktop(tester);
    final fake = FakeBiometricRepository(
      punches: [
        fakePunch(),
        fakePunch(id: 2, staffName: 'Bola Peters', employeeId: 'EMP-009'),
      ],
    );
    await tester.pumpWidget(wrap(fake));
    await openTheLog(tester);

    await tester.enterText(find.widgetWithText(TextField, 'Search the log'), 'bola');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(fake.lastPunchQuery, 'bola');
    expect(find.text('Bola Peters'), findsOneWidget);
    expect(find.text('Ada Ogun'), findsNothing);
  });

  group('uploading a file', () {
    testWidgets('somebody who may not manage the register is offered no upload', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(
        wrap(
          FakeBiometricRepository(punches: [fakePunch()]),
          actor: const AuthenticatedUser(id: 2, name: 'Teacher', email: 'teacher@example.com', role: UserRole.teacher),
        ),
      );
      await openTheLog(tester);

      expect(find.text('Ada Ogun'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Upload punches'), findsNothing);
    });

    testWidgets('the dialog says the shape of the file and that a repeat is safe', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrapDialog(FakeBiometricRepository()));
      await tester.pumpAndSettle();

      expect(find.textContaining('biometric_user_id,punched_at'), findsOneWidget);
      expect(find.textContaining('Uploading the same file twice is safe'), findsOneWidget);
    });

    group('when the file could belong to more than one school', () {
      // A file of punches has no school in it. A Super Admin, or an admin
      // over a group of branches, has to say which - the server will not
      // guess, and before this it answered a guess with "not authorized".
      const overGroup = AuthenticatedUser(
        id: 3,
        name: 'Group Admin',
        email: 'group@example.com',
        role: UserRole.schoolAdmin,
        managesBranches: true,
      );

      testWidgets('it asks, and will not upload until it is answered', (tester) async {
        useDesktop(tester);
        await tester.pumpWidget(wrapDialog(FakeBiometricRepository(), actor: overGroup));
        await tester.pumpAndSettle();

        expect(find.text('Branch'), findsOneWidget);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Choose file'));
        await tester.pumpAndSettle();

        expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upload')).onPressed, isNull);
      });

      testWidgets('the branch the screen is filtered to is the answer already', (tester) async {
        useDesktop(tester);
        final fake = FakeBiometricRepository();
        await tester.pumpWidget(wrapDialog(fake, actor: overGroup, schoolId: 7));
        await tester.pumpAndSettle();

        await tester.tap(find.widgetWithText(OutlinedButton, 'Choose file'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
        await tester.pumpAndSettle();

        expect(fake.uploaded.single['school_id'], 7);
      });

      testWidgets('an admin of one school is not asked', (tester) async {
        useDesktop(tester);
        final fake = FakeBiometricRepository();
        await tester.pumpWidget(wrapDialog(fake));
        await tester.pumpAndSettle();

        expect(find.text('Branch'), findsNothing);

        await tester.tap(find.widgetWithText(OutlinedButton, 'Choose file'));
        await tester.pumpAndSettle();
        await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
        await tester.pumpAndSettle();

        // The server files it under their own school (CLAUDE.md rule 10).
        expect(fake.uploaded.single['school_id'], isNull);
      });
    });

    testWidgets('upload is disabled until a file is chosen', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrapDialog(FakeBiometricRepository()));
      await tester.pumpAndSettle();

      final button = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upload'));
      expect(button.onPressed, isNull);
      expect(find.text('No file chosen'), findsOneWidget);
    });
  });

  group('what the outcome of a file says', () {
    Future<void> upload(WidgetTester tester, FakeBiometricRepository fake) async {
      await tester.pumpWidget(wrapDialog(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Choose file'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Upload'));
      await tester.pumpAndSettle();
    }

    testWidgets('choosing a file names it and enables the button', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository();

      await tester.pumpWidget(wrapDialog(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Choose file'));
      await tester.pumpAndSettle();

      expect(find.text('punches.csv'), findsOneWidget);
      expect(tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Upload')).onPressed, isNotNull);
    });

    testWidgets('new punches are counted', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository()
        ..uploadResult = const PunchUploadResult(read: 40, accepted: 40, duplicate: 0, refused: []);
      await upload(tester, fake);

      expect(fake.uploaded.single['file_name'], 'punches.csv');
      expect(find.text('40 new'), findsOneWidget);
    });

    testWidgets('a repeat is reported as already in, not as an error', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository()
        ..uploadResult = const PunchUploadResult(read: 40, accepted: 0, duplicate: 40, refused: []);
      await upload(tester, fake);

      expect(find.text('0 new'), findsOneWidget);
      expect(find.textContaining('40 already in'), findsOneWidget);
    });

    testWidgets('every unreadable line is listed, not just the first', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository()
        ..uploadResult = const PunchUploadResult(
          read: 3,
          accepted: 1,
          duplicate: 0,
          refused: ["Line 2: 'yesterday' is not a date and time (m/d/Y H:i).", 'Line 3: no biometric id.'],
        );
      await upload(tester, fake);

      expect(find.textContaining("Line 2: 'yesterday' is not a date"), findsOneWidget);
      expect(find.text('Line 3: no biometric id.'), findsOneWidget);
    });

    testWidgets('a failure is shown rather than swallowed', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository()..failUploadWith = Failure.network();
      await upload(tester, fake);

      expect(find.textContaining('Could not reach the server'), findsOneWidget);
    });
  });
}

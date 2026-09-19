import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:edutrack_app/features/communication/data/communication_repository.dart';
import 'package:edutrack_app/features/communication/presentation/send_notice_dialog.dart';
import 'package:edutrack_app/features/departments/data/department_repository.dart';
import 'package:edutrack_app/features/departments/data/models/department.dart';
import 'package:edutrack_app/features/staff/data/models/staff_profile.dart';
import 'package:edutrack_app/features/staff/data/staff_repository.dart';
import 'package:edutrack_app/features/students/data/models/student.dart';
import 'package:edutrack_app/features/students/data/student_repository.dart';
import 'package:edutrack_app/features/users/data/models/app_user.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/communication_fixtures.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_communication_repository.dart';
import '../../support/fake_department_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/fake_staff_repository.dart';
import '../../support/fake_student_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

const _arjun = Student(
  id: 7,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  classSectionId: 1,
  classSectionName: 'Grade 8 A',
  admissionNumber: 'ADM-001',
  firstName: 'Arjun',
  lastName: 'Kumar',
  name: 'Arjun Kumar',
  rollNumber: '12',
  guardianName: 'Raj Kumar',
  guardianMobile: '+91 9876543210',
  address: null,
  status: StudentStatus.active,
);

final _priya = StaffProfile(
  id: 3,
  userId: 20,
  employeeId: 'TCH-003',
  firstName: 'Priya',
  lastName: 'Sharma',
  name: 'Priya Sharma',
  email: 'priya@example.com',
  mobile: null,
  role: UserRole.teacher,
  status: UserStatus.active,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  departmentId: null,
  departmentName: null,
  designation: null,
  joiningDate: DateTime(2024, 6, 1),
  address: null,
  classTeacherOf: const [],
);

final _grade8 = SchoolClass(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  academicYearId: 1,
  academicYearName: '2026-27',
  name: 'Grade 8',
  level: 8,
  sections: const [
    ClassSection(id: 11, schoolClassId: 1, name: 'A', roomNumber: null, classTeacherId: null, classTeacherName: null),
  ],
);

const _maths = Department(
  id: 3,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Mathematics',
  hodUserId: null,
  hodName: null,
);

/// The dialog is opened through a real showDialog route (behind an "Open"
/// button), so popping it on success still leaves a page behind to show the
/// confirmation on.
Future<void> openDialog(WidgetTester tester, FakeCommunicationRepository fake) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        communicationRepositoryProvider.overrideWithValue(fake),
        studentRepositoryProvider.overrideWithValue(FakeStudentRepository(students: [_arjun])),
        staffRepositoryProvider.overrideWithValue(FakeStaffRepository(staff: [_priya])),
        schoolClassRepositoryProvider.overrideWithValue(FakeSchoolClassRepository(classes: [_grade8])),
        departmentRepositoryProvider.overrideWithValue(FakeDepartmentRepository(departments: const [_maths])),
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () =>
                    showDialog<void>(context: context, builder: (_) => const SendNoticeDialog(schoolId: 1)),
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ElevatedButton, 'Open'));
  await tester.pumpAndSettle();
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Lets the debounced reach count fire.
Future<void> settleReach(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

Future<void> tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

/// A dropdown currently showing [text], whatever its value type.
Finder dropdownShowing(String text) =>
    find.ancestor(of: find.text(text), matching: find.byWidgetPredicate((w) => w is DropdownButtonFormField)).first;

Future<void> chooseAudience(WidgetTester tester, String current, String wanted) async {
  await tapVisible(tester, dropdownShowing(current));
  await tester.tap(find.text(wanted).last);
  await tester.pumpAndSettle();
}

Future<void> pickArjun(WidgetTester tester) async {
  await tester.enterText(find.widgetWithText(TextFormField, 'Student'), 'Arj');
  await tester.pumpAndSettle();
  await tester.tap(find.widgetWithText(ListTile, 'Arjun Kumar - ADM-001'));
  await settleReach(tester);
}

void main() {
  testWidgets('opens on a message to one student, offering the channels the school has on', (tester) async {
    useDesktop(tester);
    await openDialog(tester, FakeCommunicationRepository());

    expect(find.text('Send Message'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Student'), findsOneWidget);
    expect(dropdownShowing('Parents / guardians'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'SMS'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'In-app'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'WhatsApp'), findsNothing);
    expect(find.widgetWithText(FilterChip, 'Email'), findsNothing);
    expect(tester.widget<FilterChip>(find.widgetWithText(FilterChip, 'SMS')).selected, isTrue);
    expect(find.widgetWithText(TextFormField, 'Subject'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Message'), findsOneWidget);
    expect(find.text('Pick who this is for to see how many people it reaches.'), findsOneWidget);
  });

  testWidgets('WhatsApp and Email are offered once the school switches them on', (tester) async {
    useDesktop(tester);
    await openDialog(tester, FakeCommunicationRepository(settings: twilioSettings));

    expect(find.widgetWithText(FilterChip, 'WhatsApp'), findsOneWidget);
    expect(find.widgetWithText(FilterChip, 'Email'), findsOneWidget);
    expect(find.text('WhatsApp needs a template mapped for this kind of message.'), findsOneWidget);
  });

  testWidgets('switching the kind changes the fields and the audience', (tester) async {
    useDesktop(tester);
    await openDialog(tester, FakeCommunicationRepository());

    await tester.tap(find.text('Fee reminder'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(TextFormField, 'Amount due'), findsOneWidget);
    expect(find.widgetWithText(TextButton, 'Pick date'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Subject'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Message'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Student'), findsOneWidget);

    await tester.tap(find.text('Emergency alert'));
    await tester.pumpAndSettle();
    expect(find.textContaining('An emergency alert goes out at once'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Subject (optional)'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Message'), findsOneWidget);
    expect(dropdownShowing('Everyone'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Send alert'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Amount due'), findsNothing);
  });

  testWidgets('each audience shows its own picker, and recipients only where they apply', (tester) async {
    useDesktop(tester);
    await openDialog(tester, FakeCommunicationRepository());

    await chooseAudience(tester, 'One student', 'One staff member');
    expect(find.widgetWithText(TextFormField, 'Staff member'), findsOneWidget);
    expect(find.widgetWithText(TextFormField, 'Student'), findsNothing);
    expect(find.text('Send to'), findsNothing);

    await chooseAudience(tester, 'One staff member', 'A class section');
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Class'), findsOneWidget);
    expect(find.text('Send to'), findsOneWidget);

    await chooseAudience(tester, 'A class section', 'A department');
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Department'), findsOneWidget);
    expect(find.text('Send to'), findsNothing);

    await chooseAudience(tester, 'A department', 'All teachers');
    expect(find.widgetWithText(DropdownButtonFormField<int>, 'Department'), findsNothing);
    expect(find.widgetWithText(TextFormField, 'Staff member'), findsNothing);
    expect(find.text('Send to'), findsNothing);

    await chooseAudience(tester, 'All teachers', 'Everyone');
    expect(find.text('Send to'), findsOneWidget);
  });

  testWidgets('picking a student counts the reach and sends to them at once', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository();
    await openDialog(tester, fake);

    await pickArjun(tester);

    expect(find.text('Reaches 5 people · SMS 5'), findsOneWidget);
    expect(fake.lastListCall, {
      'op': 'previewNotice',
      'school_id': 1,
      'kind': 'message',
      'audience_type': 'student',
      'audience_id': 7,
      'recipients': 'guardians',
      'channels': 'sms',
    });

    await tester.enterText(find.widgetWithText(TextFormField, 'Subject'), 'PTA meeting');
    await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'The PTA meets on Friday at 3 PM.');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));

    expect(fake.lastCall, {
      'op': 'sendNotice',
      'school_id': 1,
      'kind': 'message',
      'audience_type': 'student',
      'audience_id': 7,
      'recipients': 'guardians',
      'channels': ['sms'],
      'subject': 'PTA meeting',
      'body': 'The PTA meets on Friday at 3 PM.',
      'amount': null,
      'due_date': null,
    });
    expect(find.text('Send Message'), findsNothing);
    expect(find.text('Sent to 5 people.'), findsOneWidget);
  });

  testWidgets('a staff member is addressed by their login, not their profile', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository();
    await openDialog(tester, fake);

    await chooseAudience(tester, 'One student', 'One staff member');
    await tester.enterText(find.widgetWithText(TextFormField, 'Staff member'), 'Pri');
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, 'Priya Sharma - TCH-003'));
    await settleReach(tester);

    expect(fake.lastListCall!['audience_type'], 'staff_member');
    expect(fake.lastListCall!['audience_id'], 20);
    expect(fake.lastListCall!['recipients'], isNull);
  });

  testWidgets('a group is handed to the queue and the reach follows the channels', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository(noticeRecipients: 24);
    await openDialog(tester, fake);

    await chooseAudience(tester, 'One student', 'All teachers');
    await settleReach(tester);
    expect(find.text('Reaches 24 people · SMS 24'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(FilterChip, 'In-app'));
    await settleReach(tester);
    expect(find.text('Reaches 24 people · SMS 24 · In-app 24'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Subject'), 'Staff meeting');
    await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Staff meeting in the library at 4 PM.');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));

    expect(fake.lastCall!['audience_type'], 'teachers');
    expect(fake.lastCall!['audience_id'], isNull);
    expect(fake.lastCall!['recipients'], isNull);
    expect(fake.lastCall!['channels'], ['sms', 'in_app']);
    expect(find.text('Queued for 24 people.'), findsOneWidget);
  });

  testWidgets('a class section sends its id and the chosen recipients', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository();
    await openDialog(tester, fake);

    await chooseAudience(tester, 'One student', 'A class section');
    await tapVisible(tester, find.widgetWithText(DropdownButtonFormField<int>, 'Class'));
    await tester.tap(find.text('Grade 8 A').last);
    await tester.pumpAndSettle();
    await chooseAudience(tester, 'Parents / guardians', 'Both');
    await settleReach(tester);

    expect(fake.lastListCall!['audience_type'], 'class_section');
    expect(fake.lastListCall!['audience_id'], 11);
    expect(fake.lastListCall!['recipients'], 'both');
  });

  testWidgets('a fee reminder needs an amount and a due date', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository();
    await openDialog(tester, fake);

    await tester.tap(find.text('Fee reminder'));
    await tester.pumpAndSettle();
    await pickArjun(tester);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
    expect(find.text('Enter the amount due.'), findsOneWidget);
    expect(find.text('Pick the date the fee is due.'), findsOneWidget);
    expect(fake.lastCall, isNull);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount due'), '0');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
    expect(find.text('The amount must be more than zero.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Amount due'), '1500');
    await tapVisible(tester, find.widgetWithText(TextButton, 'Pick date'));
    await tester.tap(find.widgetWithText(TextButton, 'OK'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Due on '), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));

    expect(fake.lastCall!['kind'], 'fee_reminder');
    expect(fake.lastCall!['amount'], '1500');
    expect(fake.lastCall!['due_date'], matches(RegExp(r'^\d{4}-\d{2}-\d{2}$')));
    expect(fake.lastCall!['subject'], isNull);
    expect(fake.lastCall!['body'], isNull);
  });

  testWidgets('a message with nobody picked and nothing written is refused before it reaches the server', (
    tester,
  ) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository();
    await openDialog(tester, fake);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));

    expect(find.text('Pick who this message is for.'), findsOneWidget);
    expect(find.text('Enter a subject.'), findsOneWidget);
    expect(find.text('Enter the message to send.'), findsOneWidget);
    expect(fake.lastCall, isNull);

    await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Too short');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));
    expect(find.text('That message is too short.'), findsOneWidget);
    expect(fake.lastCall, isNull);
  });

  testWidgets('unticking every channel is refused', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository();
    await openDialog(tester, fake);

    await chooseAudience(tester, 'One student', 'All teachers');
    await tapVisible(tester, find.widgetWithText(FilterChip, 'SMS'));
    await settleReach(tester);
    expect(find.text('Pick a channel to see how many people this reaches.'), findsOneWidget);

    await tester.enterText(find.widgetWithText(TextFormField, 'Subject'), 'Staff meeting');
    await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'Staff meeting in the library at 4 PM.');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));

    expect(find.text('Pick at least one channel.'), findsOneWidget);
    expect(fake.lastCall, isNull);
  });

  testWidgets('an emergency alert asks before it goes out', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository(noticeRecipients: 340);
    await openDialog(tester, fake);

    await tester.tap(find.text('Emergency alert'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.widgetWithText(TextFormField, 'Message'),
      'School is closed today because of flooding.',
    );
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send alert'));

    expect(find.text('Send this emergency alert to everyone in the school?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'Back'));
    await tester.pumpAndSettle();
    expect(fake.lastCall, isNull);
    expect(find.text('Send Message'), findsOneWidget);

    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send alert'));
    await tester.tap(find.widgetWithText(FilledButton, 'Send alert').last);
    await tester.pumpAndSettle();

    expect(fake.lastCall!['kind'], 'emergency');
    expect(fake.lastCall!['audience_type'], 'everyone');
    expect(fake.lastCall!['recipients'], 'guardians');
    expect(fake.lastCall!['subject'], isNull);
    expect(fake.lastCall!['body'], 'School is closed today because of flooding.');
    expect(find.text('Queued for 340 people.'), findsOneWidget);
  });

  testWidgets('field errors from the server land under their fields and the dialog stays open', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository();
    await openDialog(tester, fake);

    await pickArjun(tester);
    await tester.enterText(find.widgetWithText(TextFormField, 'Subject'), 'PTA meeting');
    await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'The PTA meets on Friday at 3 PM.');

    fake.failWith = const Failure(
      code: 'VALIDATION_ERROR',
      message: 'The given data was invalid.',
      details: {
        'errors': {
          'channels': ['WhatsApp and Email is switched off for this school.'],
          'subject': ['The subject field is required.'],
        },
      },
    );
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));

    expect(find.text('Send Message'), findsOneWidget);
    expect(find.text('The given data was invalid.'), findsOneWidget);
    expect(find.text('WhatsApp and Email is switched off for this school.'), findsOneWidget);
    expect(find.text('The subject field is required.'), findsOneWidget);

    // Changing anything clears the stale rejection.
    fake.failWith = null;
    await tapVisible(tester, find.widgetWithText(FilterChip, 'In-app'));
    expect(find.text('The given data was invalid.'), findsNothing);
    expect(find.text('The subject field is required.'), findsNothing);
  });

  testWidgets('an unreachable audience is said plainly', (tester) async {
    useDesktop(tester);
    final fake = FakeCommunicationRepository();
    await openDialog(tester, fake);

    // Guardians have no inbox, so in-app alone reaches nobody.
    await tapVisible(tester, find.widgetWithText(FilterChip, 'SMS'));
    await tapVisible(tester, find.widgetWithText(FilterChip, 'In-app'));
    await pickArjun(tester);

    expect(find.text('Nobody in this audience can be reached on these channels.'), findsOneWidget);

    fake.failWith = const Failure(code: 'UNREACHABLE_AUDIENCE', message: 'Nobody in this audience can be reached.');
    await tester.enterText(find.widgetWithText(TextFormField, 'Subject'), 'PTA meeting');
    await tester.enterText(find.widgetWithText(TextFormField, 'Message'), 'The PTA meets on Friday at 3 PM.');
    await tapVisible(tester, find.widgetWithText(FilledButton, 'Send'));

    expect(find.text('Nobody in this audience can be reached.'), findsOneWidget);
    expect(find.text('Send Message'), findsOneWidget);
  });
}

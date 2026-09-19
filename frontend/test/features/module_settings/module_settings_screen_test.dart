import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/module_settings/data/module_settings_repository.dart';
import 'package:edutrack_app/features/module_settings/presentation/module_settings_screen.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_module_settings_repository.dart';
import '../../support/fake_school_repository.dart';

const _superAdmin = AuthenticatedUser(
  id: 1,
  name: 'Platform Owner',
  email: 'owner@example.com',
  role: UserRole.superAdmin,
);
const _schoolAdmin = AuthenticatedUser(
  id: 2,
  name: 'Anita Sharma',
  email: 'anita@example.com',
  role: UserRole.schoolAdmin,
);

const _school = School(
  id: 1,
  name: 'Sunrise Public School',
  registrationNumber: null,
  email: 'admin@sunriseschool.edu',
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

Widget wrap(FakeModuleSettingsRepository fake, {AuthenticatedUser actor = _schoolAdmin}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      moduleSettingsRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: const [_school])),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: ModuleSettingsScreen()),
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

/// A School Admin's list is loaded straight away; a Super Admin's only once
/// they have picked a school.
Future<void> pumpAsSchoolAdmin(WidgetTester tester, FakeModuleSettingsRepository fake) async {
  await tester.pumpWidget(wrap(fake));
  await tester.pumpAndSettle();
}

Future<void> pumpAsSuperAdminWithSchool(WidgetTester tester, FakeModuleSettingsRepository fake) async {
  await tester.pumpWidget(wrap(fake, actor: _superAdmin));
  await tester.pumpAndSettle();
  await tester.tap(find.byType(DropdownButtonFormField<int>));
  await tester.pumpAndSettle();
  await tester.tap(find.text('Sunrise Public School').last);
  await tester.pumpAndSettle();
}

bool switchValue(WidgetTester tester, Key key) => tester.widget<SwitchListTile>(find.byKey(key)).value;

bool switchEnabled(WidgetTester tester, Key key) => tester.widget<SwitchListTile>(find.byKey(key)).onChanged != null;

Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
}

/// Each module on its own card: the platform's switch and the school's, the
/// module's own settings, and a confirmation before anything is switched off.
void main() {
  testWidgets('shows a spinner while the modules load', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository()..listGate = Completer<void>();
    await tester.pumpWidget(wrap(fake));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.byKey(const ValueKey('module-card-students')), findsNothing);

    fake.listGate!.complete();
    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.byKey(const ValueKey('module-card-students')), findsOneWidget);
  });

  testWidgets('a failed load shows the error and retries on request', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository(
      failListWith: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
    );
    await pumpAsSchoolAdmin(tester, fake);

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.byKey(const ValueKey('module-card-students')), findsNothing);

    fake.failListWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(fake.listCalls, 2);
    expect(find.byKey(const ValueKey('module-card-students')), findsOneWidget);
  });

  testWidgets('a super admin has to pick a school before anything loads', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository();
    await tester.pumpWidget(wrap(fake, actor: _superAdmin));
    await tester.pumpAndSettle();

    expect(find.text('Module Settings'), findsOneWidget);
    expect(find.text('Pick a school to configure its modules.'), findsOneWidget);
    expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
    expect(fake.listCalls, 0);

    await tester.tap(find.byType(DropdownButtonFormField<int>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sunrise Public School').last);
    await tester.pumpAndSettle();

    expect(fake.listCalls, 1);
    expect(fake.lastListSchoolId, 1);
    expect(find.text('Pick a school to configure its modules.'), findsNothing);
    expect(find.byKey(const ValueKey('module-card-attendance')), findsOneWidget);
  });

  testWidgets('a school admin gets their own school, with no picker', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository(rows: defaultModuleSettings(canChangePlatform: false));
    await pumpAsSchoolAdmin(tester, fake);

    expect(find.byType(DropdownButtonFormField<int>), findsNothing);
    expect(find.text('Pick a school to configure its modules.'), findsNothing);
    expect(fake.lastListSchoolId, isNull);
    expect(find.byKey(const ValueKey('module-card-students')), findsOneWidget);
  });

  testWidgets('renders a card per module with its switches and settings', (tester) async {
    useDesktop(tester);
    await pumpAsSuperAdminWithSchool(tester, FakeModuleSettingsRepository());

    expect(find.text('Students'), findsOneWidget);
    expect(find.text('Student Attendance'), findsOneWidget);
    expect(find.text('Payroll'), findsOneWidget);
    expect(find.text('Daily registers, per section.'), findsOneWidget);

    // The spine: always on, and neither switch can be moved.
    expect(find.text('Always on'), findsOneWidget);
    expect(switchEnabled(tester, const Key('module-school-students')), isFalse);
    expect(switchValue(tester, const Key('module-school-students')), isTrue);
    expect(switchEnabled(tester, const Key('module-platform-students')), isFalse);

    // A switchable module: the Super Admin holds both switches.
    expect(switchEnabled(tester, const Key('module-platform-attendance')), isTrue);
    expect(switchEnabled(tester, const Key('module-school-attendance')), isTrue);
    expect(switchValue(tester, const Key('module-platform-attendance')), isTrue);
    expect(switchValue(tester, const Key('module-school-attendance')), isTrue);

    // Its settings, from the schema: a number with its help, saved on the button.
    final lateDays = find.byKey(const Key('module-setting-attendance-late_days'));
    expect(lateDays, findsOneWidget);
    expect(tester.widget<TextFormField>(lateDays).controller!.text, '30');
    expect(find.text('0 means today only.'), findsOneWidget);
    expect(tester.widget<FilledButton>(find.byKey(const Key('module-save-attendance'))).onPressed, isNull);

    await scrollTo(tester, find.byKey(const ValueKey('module-card-payroll')));
    // A flag setting is a switch.
    expect(find.byKey(const Key('module-setting-payroll-email_payslips')), findsOneWidget);
    expect(switchValue(tester, const Key('module-setting-payroll-email_payslips')), isTrue);

    await scrollTo(tester, find.byKey(const ValueKey('module-card-timetable')));
    // No settings: no form, no save.
    expect(find.byKey(const Key('module-save-timetable')), findsNothing);
  });

  testWidgets('switching a module off asks first, then sends that switch alone', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository();
    await pumpAsSuperAdminWithSchool(tester, fake);

    await tester.tap(find.byKey(const Key('module-school-attendance')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(
      find.text(
        'Switch off Student Attendance for this school? Its screens and API are refused until it is on again; '
        'nothing is deleted.',
      ),
      findsOneWidget,
    );
    expect(fake.updateCalls, 0);

    await tester.tap(find.widgetWithText(FilledButton, 'Switch off'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.lastUpdate, {
      'module': 'attendance',
      'school_id': 1,
      'platform_enabled': null,
      'school_enabled': false,
      'settings': null,
    });
    expect(switchValue(tester, const Key('module-school-attendance')), isFalse);
    expect(find.text('Off'), findsOneWidget);
    expect(find.text('Updated by Anita Sharma'), findsOneWidget);
  });

  testWidgets('cancelling the confirmation leaves the switch where it was', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository();
    await pumpAsSuperAdminWithSchool(tester, fake);

    await tester.tap(find.byKey(const Key('module-school-attendance')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await tester.pumpAndSettle();

    expect(fake.updateCalls, 0);
    expect(switchValue(tester, const Key('module-school-attendance')), isTrue);
  });

  testWidgets('switching a module back on needs no confirmation', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository(
      rows: [
        moduleSetting(schoolEnabled: false, settingsSchema: const [lateDaysField]),
      ],
    );
    await pumpAsSuperAdminWithSchool(tester, fake);
    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.byKey(const Key('module-school-attendance')));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsNothing);
    expect(fake.lastUpdate!['school_enabled'], isTrue);
    expect(switchValue(tester, const Key('module-school-attendance')), isTrue);
    expect(find.text('Off'), findsNothing);
  });

  testWidgets('withdrawing a module at the platform asks in its own words', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository();
    await pumpAsSuperAdminWithSchool(tester, fake);

    await tester.tap(find.byKey(const Key('module-platform-attendance')));
    await tester.pumpAndSettle();

    expect(find.text('Withdraw Student Attendance?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Withdraw'));
    await tester.pumpAndSettle();

    expect(fake.lastUpdate!['platform_enabled'], isFalse);
    expect(fake.lastUpdate!['school_enabled'], isNull);
    expect(switchValue(tester, const Key('module-platform-attendance')), isFalse);
  });

  testWidgets('a school admin never sees the platform switch', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository(rows: defaultModuleSettings(canChangePlatform: false));
    await pumpAsSchoolAdmin(tester, fake);

    expect(find.byKey(const Key('module-platform-attendance')), findsNothing);
    expect(find.byKey(const Key('module-platform-students')), findsNothing);
    expect(find.byKey(const Key('module-school-attendance')), findsOneWidget);
    expect(switchEnabled(tester, const Key('module-school-attendance')), isTrue);
    expect(find.text('Not granted by the platform'), findsNothing);
  });

  testWidgets('a module the platform has not granted is marked and locked for a school admin', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository(rows: [moduleSetting(platformEnabled: false, canChangePlatform: false)]);
    await pumpAsSchoolAdmin(tester, fake);

    expect(find.text('Not granted by the platform'), findsOneWidget);
    expect(find.byKey(const Key('module-platform-attendance')), findsNothing);
    expect(switchEnabled(tester, const Key('module-school-attendance')), isFalse);
    expect(switchValue(tester, const Key('module-school-attendance')), isTrue);
  });

  testWidgets('a school switch the server refuses shows its reason under the switch', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository(
      rows: defaultModuleSettings(canChangePlatform: false),
      failUpdateWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The platform has not granted this module.',
        details: {
          'errors': {
            'school_enabled': ['The platform has not granted this module.'],
          },
        },
      ),
    );
    await pumpAsSchoolAdmin(tester, fake);

    await tester.tap(find.byKey(const Key('module-school-attendance')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Switch off'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('module-switch-error-attendance')), findsOneWidget);
    expect(find.text('The platform has not granted this module.'), findsOneWidget);
    // The switch shows what the server still has.
    expect(switchValue(tester, const Key('module-school-attendance')), isTrue);
  });

  testWidgets('a setting outside its range is refused before it reaches the server', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository();
    await pumpAsSuperAdminWithSchool(tester, fake);
    final lateDays = find.byKey(const Key('module-setting-attendance-late_days'));
    final save = find.byKey(const Key('module-save-attendance'));

    await tester.enterText(lateDays, '400');
    await tester.pumpAndSettle();
    expect(tester.widget<FilledButton>(save).onPressed, isNotNull);

    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Days a register may be marked late must be at most 365'), findsOneWidget);
    expect(fake.updateCalls, 0);

    await tester.enterText(lateDays, '');
    await tester.tap(save);
    await tester.pumpAndSettle();
    expect(find.text('Days a register may be marked late must be a whole number'), findsOneWidget);
    expect(fake.updateCalls, 0);
  });

  testWidgets("saving sends that module's settings alone and says so", (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository();
    await pumpAsSuperAdminWithSchool(tester, fake);
    final lateDays = find.byKey(const Key('module-setting-attendance-late_days'));
    final save = find.byKey(const Key('module-save-attendance'));

    await tester.enterText(lateDays, '3');
    await tester.pumpAndSettle();
    await tester.tap(save);
    await tester.pumpAndSettle();

    expect(fake.lastUpdate, {
      'module': 'attendance',
      'school_id': 1,
      'platform_enabled': null,
      'school_enabled': null,
      'settings': {'late_days': 3},
    });
    expect(find.text('Settings saved.'), findsOneWidget);
    expect(find.text('Updated by Anita Sharma'), findsOneWidget);
    // Saved: nothing left to save until it is changed again.
    expect(tester.widget<FilledButton>(save).onPressed, isNull);
    expect(tester.widget<TextFormField>(lateDays).controller!.text, '3');
  });

  testWidgets('a flag setting saves as a bool', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository();
    await pumpAsSuperAdminWithSchool(tester, fake);
    await scrollTo(tester, find.byKey(const ValueKey('module-card-payroll')));

    await tester.tap(find.byKey(const Key('module-setting-payroll-email_payslips')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('module-save-payroll')));
    await tester.pumpAndSettle();

    expect(fake.lastUpdate!['module'], 'payroll');
    expect(fake.lastUpdate!['settings'], {'email_payslips': false});
    expect(find.text('Settings saved.'), findsOneWidget);
  });

  testWidgets('a save the server refuses shows its sentence under the form', (tester) async {
    useDesktop(tester);
    final fake = FakeModuleSettingsRepository(
      failUpdateWith: const Failure(
        code: 'VALIDATION_ERROR',
        message: 'late_days must be between 0 and 365.',
        details: {
          'errors': {
            'settings': ['late_days must be between 0 and 365.'],
          },
        },
      ),
    );
    await pumpAsSuperAdminWithSchool(tester, fake);

    await tester.enterText(find.byKey(const Key('module-setting-attendance-late_days')), '5');
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('module-save-attendance')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('module-settings-error-attendance')), findsOneWidget);
    expect(find.text('late_days must be between 0 and 365.'), findsOneWidget);
    expect(find.text('Settings saved.'), findsNothing);
    // Still editable and still dirty: the form did not fall into an error state.
    expect(tester.widget<FilledButton>(find.byKey(const Key('module-save-attendance'))).onPressed, isNotNull);
  });

  testWidgets('fits a phone: the cards stack and nothing overflows', (tester) async {
    usePhone(tester);
    await pumpAsSchoolAdmin(
      tester,
      FakeModuleSettingsRepository(rows: defaultModuleSettings(canChangePlatform: false)),
    );

    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('module-card-students')), findsOneWidget);
    expect(find.byKey(const Key('module-school-attendance')), findsOneWidget);
  });
}

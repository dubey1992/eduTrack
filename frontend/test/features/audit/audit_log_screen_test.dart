import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/school_clock.dart';
import 'package:edutrack_app/features/audit/data/audit_log_repository.dart';
import 'package:edutrack_app/features/audit/presentation/audit_log_screen.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_audit_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';
import '../../support/paginated_table.dart';

/// The school's day is 18 September 2026 whatever the machine running the
/// tests thinks, so the date picker's bounds are predictable.
final _clock = SchoolClock(
  timezone: 'Asia/Kolkata',
  schoolTimeAtAnchor: DateTime(2026, 9, 18, 10),
  anchorUtc: DateTime.now().toUtc(),
);

final _schoolAdmin = AuthenticatedUser(
  id: 2,
  name: 'Anita Sharma',
  email: 'anita@example.com',
  role: UserRole.schoolAdmin,
  clock: _clock,
);

final _superAdmin = AuthenticatedUser(
  id: 1,
  name: 'Platform Owner',
  email: 'owner@example.com',
  role: UserRole.superAdmin,
  clock: _clock,
);

Widget wrap(FakeAuditRepository fake, {AuthenticatedUser? actor}) {
  return ProviderScope(
    retry: (retryCount, error) => null,
    overrides: [
      auditLogRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor ?? _schoolAdmin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: AuditLogScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void usePhone(WidgetTester tester) {
  tester.view.physicalSize = const Size(400, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

/// Phase 21's audit log: read-only, filtered server-side, and honest about
/// who did what - including a sign-in attempt nobody owns.
void main() {
  testWidgets('shows who did what to which record', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeAuditRepository(entries: [auditEntry()])));
    await tester.pumpAndSettle();

    expect(find.text('Audit Log'), findsOneWidget);
    expect(find.text('Anita Sharma'), findsOneWidget);
    expect(find.text('School Admin'), findsOneWidget);
    expect(find.text('Student updated'), findsOneWidget);
    expect(find.text('Student #42'), findsOneWidget);
    expect(find.text('Students'), findsOneWidget);
    expect(find.text('09/16/2026 3:53 PM'), findsOneWidget);
    expect(find.text('10.0.0.5'), findsOneWidget);
  });

  testWidgets('choosing a module asks the API for that module only', (tester) async {
    useDesktop(tester);
    final fake = FakeAuditRepository(entries: [auditEntry()]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();
    expect(fake.lastModule, isNull);

    await tester.tap(find.byKey(const Key('audit-module-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Payments').last);
    await tester.pumpAndSettle();

    expect(fake.lastModule, 'payments');
  });

  testWidgets('a picked date range is sent as from and to', (tester) async {
    useDesktop(tester);
    final fake = FakeAuditRepository(entries: [auditEntry()]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.text('All dates'));
    await tester.pumpAndSettle();
    // Typing the dates is steadier than tapping a calendar.
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).at(0), '09/01/2026');
    await tester.enterText(find.byType(TextField).at(1), '09/15/2026');
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();

    expect((fake.lastFrom, fake.lastTo), ('2026-09-01', '2026-09-15'));
    expect(find.text('09/01/2026 - 09/15/2026'), findsOneWidget);

    await tester.tap(find.byTooltip('Clear dates'));
    await tester.pumpAndSettle();

    expect((fake.lastFrom, fake.lastTo), (null, null));
  });

  testWidgets('exporting asks for the CSV of the entries on screen', (tester) async {
    useDesktop(tester);
    final fake = FakeAuditRepository(entries: [auditEntry()]);
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('audit-module-filter')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Sign-in & security').last);
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export CSV'));
    await tester.pumpAndSettle();

    expect(fake.downloadCalls, 1);
    expect(fake.lastDownloadFilters, {'school_id': null, 'module': 'auth', 'from': null, 'to': null});
    // Off the web there is no download mechanism wired up yet; the message
    // has to reach the user instead of the button appearing to work.
    expect(find.textContaining('only available in the web app'), findsOneWidget);
  });

  testWidgets('an export the server refuses says why', (tester) async {
    useDesktop(tester);
    final fake = FakeAuditRepository(
      entries: [auditEntry()],
      failDownloadWith: const Failure(code: 'FORBIDDEN', message: 'You cannot export the audit log.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, 'Export CSV'));
    await tester.pumpAndSettle();

    expect(find.text('You cannot export the audit log.'), findsOneWidget);
  });

  testWidgets('the detail of an update shows each field before and after', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeAuditRepository(entries: [auditEntry()])));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(TextButton, 'View'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Before')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('After')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('First name')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Arjun')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Arjun K')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('8A')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('8B')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Anita Sharma (School Admin)')), findsOneWidget);
  });

  testWidgets('the detail of a creation shows one Value column, nested values as JSON', (tester) async {
    useDesktop(tester);
    final created = auditEntry(
      module: 'transport',
      action: 'vehicle.created',
      entityType: 'vehicle',
      entityId: 4,
      oldValues: null,
      newValues: const {
        'registration_number': 'KA-01-1234',
        'capacity': 40,
        'is_active': true,
        'notes': null,
        'meta': {'fuel': 'diesel'},
      },
    );
    await tester.pumpWidget(wrap(FakeAuditRepository(entries: [created])));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Vehicle created'));
    await tester.pumpAndSettle();

    final dialog = find.byType(AlertDialog);
    expect(find.descendant(of: dialog, matching: find.text('Value')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Before')), findsNothing);
    expect(find.descendant(of: dialog, matching: find.text('Registration number')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('KA-01-1234')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('40')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('Yes')), findsOneWidget);
    expect(find.descendant(of: dialog, matching: find.text('-')), findsWidgets);
    expect(find.descendant(of: dialog, matching: find.text('{"fuel":"diesel"}')), findsOneWidget);
  });

  testWidgets('an entry with no values says so rather than showing an empty table', (tester) async {
    useDesktop(tester);
    final signedOut = auditEntry(module: 'auth', action: 'user.signed_out', oldValues: null, newValues: null);
    await tester.pumpWidget(wrap(FakeAuditRepository(entries: [signedOut])));
    await tester.pumpAndSettle();

    // A tap anywhere on the row opens it, not just the View button.
    await tester.tap(find.text('User signed out'));
    await tester.pumpAndSettle();

    expect(find.text('No field changes recorded.'), findsOneWidget);
    expect(find.text('Value'), findsNothing);
  });

  testWidgets('a failed sign-in with no account shows the address that was tried', (tester) async {
    useDesktop(tester);
    final failed = auditEntry(
      userId: null,
      userName: null,
      userRole: null,
      module: 'auth',
      action: 'user.sign_in_failed',
      entityType: 'user',
      entityId: null,
      oldValues: null,
      newValues: const {'email': 'ghost@example.com'},
    );
    await tester.pumpWidget(wrap(FakeAuditRepository(entries: [failed])));
    await tester.pumpAndSettle();

    expect(find.text('ghost@example.com'), findsOneWidget);
    expect(find.text('User sign in failed'), findsOneWidget);
    expect(find.text('Sign-in & security'), findsWidgets);
  });

  testWidgets('says so when no entry matches the filters', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeAuditRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No audit entries match these filters.'), findsOneWidget);
  });

  testWidgets('a failed load shows the error and retries on request', (tester) async {
    useDesktop(tester);
    final fake = FakeAuditRepository(
      entries: [auditEntry()],
      failListWith: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);

    fake.failListWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();

    expect(find.text('Student updated'), findsOneWidget);
  });

  testWidgets('fits a phone: cards instead of a table, and the detail opens', (tester) async {
    usePhone(tester);
    await tester.pumpWidget(wrap(FakeAuditRepository(entries: [auditEntry()])));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(DataTable), findsNothing);
    expect(find.text('Student updated'), findsOneWidget);
    expect(find.text('Anita Sharma · School Admin'), findsOneWidget);

    await tester.tap(find.text('Student updated'));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Arjun K'), findsOneWidget);
  });

  testWidgets('a super admin sees which school each entry belongs to', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(
        FakeAuditRepository(entries: [auditEntry(), auditEntry(id: 2, schoolId: null, schoolName: null)]),
        actor: _superAdmin,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('School'), findsOneWidget);
    expect(find.text('Green Valley School'), findsOneWidget);
    // An entry with no school is the platform's own.
    expect(find.text('Platform'), findsOneWidget);
  });

  testWidgets('a school admin does not get a School column', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeAuditRepository(entries: [auditEntry()])));
    await tester.pumpAndSettle();

    expect(find.text('School'), findsNothing);
    expect(find.text('Green Valley School'), findsNothing);
  });

  testWidgets('a full page of entries scrolls above the pagination bar on desktop', (tester) async {
    useShortDesktopWindow(tester);
    final entries = [for (var i = 1; i <= 20; i++) auditEntry(id: i, userName: 'User $i')];
    await tester.pumpWidget(wrap(FakeAuditRepository(entries: entries)));
    await tester.pumpAndSettle();

    await expectLastRowScrollsAbovePagination(tester, find.text('User 20'));
  });
}

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/guardian_invites/data/guardian_invites.dart';
import 'package:edutrack_app/features/guardian_invites/presentation/guardian_invites_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/session_users.dart';

/// Guardian Requests as the office sees them (docs/mobile-apps-review.md, M8, 8.5).
class FakeGuardianInvitesRepository implements GuardianInvitesRepository {
  FakeGuardianInvitesRepository({this.empty = false, this.failListWith, this.failDecideWith});

  bool empty;
  Failure? failListWith;
  Failure? failDecideWith;
  final List<GuardianInviteStatus> listed = [];
  final List<int> approved = [];
  final List<int> declined = [];

  static GuardianInvite invite({GuardianInviteStatus status = GuardianInviteStatus.pending}) => GuardianInvite(
    id: 7,
    name: 'Rohan Sharma',
    mobile: '+91 91234 56780',
    relationship: 'father',
    status: status,
    studentId: 3,
    studentName: 'Aarav Sharma',
    admissionNumber: 'ADM-001',
    classSectionName: 'Grade 5 - A',
    requestedByName: 'Meera Sharma',
    decidedByName: status == GuardianInviteStatus.pending ? null : 'Office Admin',
  );

  @override
  Future<PaginatedResponse<GuardianInvite>> list({required GuardianInviteStatus status, int page = 1}) async {
    listed.add(status);
    if (failListWith != null) throw failListWith!;
    final items = empty ? <GuardianInvite>[] : [invite(status: status)];
    return PaginatedResponse(items: items, currentPage: 1, lastPage: 1, total: items.length, perPage: 20);
  }

  @override
  Future<GuardianInvite> approve(int inviteId) async {
    if (failDecideWith != null) throw failDecideWith!;
    approved.add(inviteId);
    return invite(status: GuardianInviteStatus.approved);
  }

  @override
  Future<GuardianInvite> decline(int inviteId) async {
    if (failDecideWith != null) throw failDecideWith!;
    declined.add(inviteId);
    return invite(status: GuardianInviteStatus.declined);
  }
}

Future<FakeGuardianInvitesRepository> pump(WidgetTester tester, {FakeGuardianInvitesRepository? fake}) async {
  final repository = fake ?? FakeGuardianInvitesRepository();
  tester.view.physicalSize = const Size(1200, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [guardianInvitesRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: GuardianInvitesScreen()),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return repository;
}

void main() {
  testWidgets('opens on the waiting requests: who, for which child, asked by whom', (tester) async {
    final fake = await pump(tester);

    expect(fake.listed, [GuardianInviteStatus.pending]);
    expect(find.text('Rohan Sharma · Father'), findsOneWidget);
    expect(find.text('For Aarav Sharma (ADM-001 · Grade 5 - A)'), findsOneWidget);
    expect(find.textContaining('Asked by Meera Sharma'), findsOneWidget);
    expect(find.byKey(const Key('guardian-invite-approve-7')), findsOneWidget);
  });

  testWidgets('Approve asks first, then adds the guardian', (tester) async {
    final fake = await pump(tester);

    await tester.tap(find.byKey(const Key('guardian-invite-approve-7')));
    await tester.pumpAndSettle();
    expect(find.text('Approve Rohan Sharma?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(fake.approved, [7]);
    expect(find.text('Rohan Sharma added as a guardian.'), findsOneWidget);
    expect(fake.listed.length, 2, reason: 'the list reloads');
  });

  testWidgets('cancelling the question changes nothing', (tester) async {
    final fake = await pump(tester);

    await tester.tap(find.byKey(const Key('guardian-invite-decline-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(fake.declined, isEmpty);
    expect(fake.approved, isEmpty);
  });

  testWidgets('Decline asks first, then declines', (tester) async {
    final fake = await pump(tester);

    await tester.tap(find.byKey(const Key('guardian-invite-decline-7')));
    await tester.pumpAndSettle();
    expect(find.text('Decline this request?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Decline'));
    await tester.pumpAndSettle();

    expect(fake.declined, [7]);
    expect(find.text('Request declined.'), findsOneWidget);
  });

  testWidgets("the server's refusal is shown as it said it", (tester) async {
    final fake = FakeGuardianInvitesRepository(
      failDecideWith: const Failure(code: 'GUARDIAN_PROBLEM', message: 'This request was already decided.'),
    );
    await pump(tester, fake: fake);

    await tester.tap(find.byKey(const Key('guardian-invite-approve-7')));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Approve').last);
    await tester.pumpAndSettle();

    expect(find.text('This request was already decided.'), findsOneWidget);
  });

  testWidgets('decided requests carry no buttons and say who decided', (tester) async {
    final fake = await pump(tester);

    await tester.tap(find.text('Approved'));
    await tester.pumpAndSettle();

    expect(fake.listed.last, GuardianInviteStatus.approved);
    expect(find.textContaining('approved by Office Admin'), findsOneWidget);
    expect(find.byKey(const Key('guardian-invite-approve-7')), findsNothing);
  });

  testWidgets('nothing waiting says so', (tester) async {
    await pump(tester, fake: FakeGuardianInvitesRepository(empty: true));

    expect(find.text('No requests waiting.'), findsOneWidget);
  });

  testWidgets('a failed load says so and retries', (tester) async {
    final fake = FakeGuardianInvitesRepository(failListWith: Failure.network());
    await pump(tester, fake: fake);
    expect(find.text(Failure.network().message), findsOneWidget);

    fake.failListWith = null;
    await tester.tap(find.text('Retry'));
    await tester.pumpAndSettle();
    expect(find.text('Rohan Sharma · Father'), findsOneWidget);
  });

  group('the menu entry', () {
    final item = AppNav.findByPath('/guardian-requests')!;

    test('shows to the school admin when the Family app is on', () {
      expect(item.allows(sessionUser(UserRole.schoolAdmin, modules: {AppModules.familyApp: true})), isTrue);
    });

    test('is hidden while the school has the Family app off', () {
      expect(item.allows(sessionUser(UserRole.schoolAdmin, modules: {AppModules.familyApp: false})), isFalse);
    });

    test('is hidden when Students is off', () {
      final user = sessionUser(UserRole.schoolAdmin, modules: {AppModules.familyApp: true, AppModules.students: false});
      expect(item.allows(user), isFalse);
    });

    test('is not for teachers or the accountant', () {
      for (final role in [UserRole.teacher, UserRole.hod, UserRole.accountant]) {
        expect(item.allows(sessionUser(role, modules: {AppModules.familyApp: true})), isFalse, reason: role.name);
      }
    });
  });
}

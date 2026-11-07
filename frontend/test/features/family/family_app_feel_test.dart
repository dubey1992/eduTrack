import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/family/data/family_device_storage.dart';
import 'package:edutrack_app/features/family/data/models/family_account.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart' show pumpFamilyApp;

/// The Family app behaving like the other two phone apps: it opens at once,
/// keeps the last copy without signal, shows only what the school uses, has
/// the bell on every tab, and Back goes Home before it leaves.
void main() {
  testWidgets('opens on the saved account without waiting for the server', (tester) async {
    final auth = FakeFamilyAuthRepository(account: familyAccount(), saved: familyAccount());
    await pumpFamilyApp(tester, auth: auth);

    expect(find.byKey(const Key('family-home')), findsOneWidget);
    // And still asks the server behind it.
    expect(auth.restores, 1);
  });

  testWidgets('a server that ended the session signs out after the instant start', (tester) async {
    await pumpFamilyApp(tester, auth: FakeFamilyAuthRepository(saved: familyAccount()));

    expect(find.byKey(const Key('family-sign-in')), findsOneWidget);
  });

  testWidgets('with no signal, Home shows the copy saved on the phone and says from when', (tester) async {
    final data = FakeFamilyRepository(failTodayWith: Failure.network())
      ..savedTodayValue = (today: familyToday(), at: DateTime(2026, 11, 6, 8, 42));
    await pumpFamilyApp(tester, data: data);

    expect(find.text('Aarav is in school'), findsOneWidget);
    expect(find.text('No connection. Showing what was true at 11/06/2026 8:42 AM.'), findsOneWidget);
  });

  testWidgets('with no signal and nothing saved, it says so with a retry', (tester) async {
    await pumpFamilyApp(tester, data: FakeFamilyRepository(failTodayWith: Failure.network()));

    expect(find.byKey(const Key('family-retry')), findsOneWidget);
  });

  testWidgets('no Bus tab when no child takes the bus, and no Fees tab where the school has no fees', (tester) async {
    const noFees = FamilyFeatures(fees: false, transport: true, results: true, timetable: true, syllabus: true);
    await pumpFamilyApp(
      tester,
      auth: FakeFamilyAuthRepository(account: familyAccount(features: noFees)),
    );

    expect(find.byKey(const Key('family-nav-bus')), findsNothing);
    expect(find.byKey(const Key('family-nav-fees')), findsNothing);
    expect(find.byKey(const Key('family-nav-attendance')), findsOneWidget);
  });

  testWidgets('a child on the bus brings the Bus tab', (tester) async {
    const onBus = FamilyChild(
      id: 11,
      firstName: 'Aarav',
      lastName: 'Sharma',
      className: 'Class 6 A',
      rollNumber: '4',
      hasTransport: true,
    );
    await pumpFamilyApp(
      tester,
      auth: FakeFamilyAuthRepository(account: familyAccount(children: const [onBus])),
    );

    expect(find.byKey(const Key('family-nav-bus')), findsOneWidget);
  });

  testWidgets('More lists only the learning screens the school uses', (tester) async {
    const testsOnly = FamilyFeatures(fees: true, transport: true, results: true, timetable: false, syllabus: false);
    await pumpFamilyApp(
      tester,
      auth: FakeFamilyAuthRepository(account: familyAccount(features: testsOnly)),
      goTo: '/more',
    );

    expect(find.byKey(const Key('family-more-results')), findsOneWidget);
    expect(find.byKey(const Key('family-more-timetable')), findsNothing);
    expect(find.byKey(const Key('family-more-syllabus')), findsNothing);
  });

  testWidgets('the bell on every tab counts the unread and opens Notices', (tester) async {
    await pumpFamilyApp(
      tester,
      data: FakeFamilyRepository(notices: [familyNotice(), familyNotice(id: 2)]),
      goTo: '/attendance',
    );

    expect(find.descendant(of: find.byKey(const Key('family-bell')), matching: find.text('2')), findsOneWidget);
    await tester.tap(find.byKey(const Key('family-bell')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('family-notices')), findsOneWidget);
  });

  testWidgets('Back on another tab goes Home first', (tester) async {
    await pumpFamilyApp(tester, goTo: '/attendance');

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('family-home')), findsOneWidget);
  });

  testWidgets('a forgotten passcode leads to the setup code from a new letter', (tester) async {
    await pumpFamilyApp(
      tester,
      auth: FakeFamilyAuthRepository(
        device: const FamilyDevice(mobile: '+91 9876543210', secret: 'secret'),
      ),
    );

    await tester.tap(find.byKey(const Key('family-forgot-passcode')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('family-forgot-dialog')), findsOneWidget);

    await tester.tap(find.byKey(const Key('family-have-new-code')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('family-setup-code')), findsOneWidget);
  });
}

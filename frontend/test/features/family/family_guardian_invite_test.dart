import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/widgets/phone_number_field.dart';
import 'package:edutrack_app/features/family/data/models/family_guardian_invite.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart' show pumpFamilyApp;

/// "Add a guardian" in the Family app (docs/mobile-apps-review.md, M8, 8.5):
/// the parent asks; the school decides.
void main() {
  Future<void> fill(WidgetTester tester, {String name = 'Rohan Sharma', String mobile = '9123456780'}) async {
    await tester.enterText(find.byKey(const Key('family-guardian-name')), name);
    await tester.enterText(
      find.descendant(of: find.byType(PhoneNumberField), matching: find.byType(TextField)).last,
      mobile,
    );
    await tester.tap(find.byKey(const Key('family-guardian-relationship')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Father').last);
    await tester.pumpAndSettle();
  }

  testWidgets('More leads to Add a guardian', (tester) async {
    await pumpFamilyApp(tester, goTo: '/more');

    expect(find.byKey(const Key('family-more-guardian')), findsOneWidget);
  });

  testWidgets('a request goes to the school and waits there', (tester) async {
    final data = FakeFamilyRepository();
    await pumpFamilyApp(tester, data: data, goTo: '/guardians/new');

    await fill(tester);
    await tester.tap(find.byKey(const Key('family-guardian-send')));
    await tester.pumpAndSettle();

    final ask = data.guardianAsks.single;
    expect((ask.name, ask.relationship), ('Rohan Sharma', 'father'));
    expect(ask.mobile, contains('9123456780'));
    expect(find.text('Sent. The school will look at your request.'), findsOneWidget);
    expect(find.text('Waiting for the school'), findsOneWidget);
  });

  testWidgets('nothing is sent without a name and a relationship', (tester) async {
    final data = FakeFamilyRepository();
    await pumpFamilyApp(tester, data: data, goTo: '/guardians/new');

    await tester.tap(find.byKey(const Key('family-guardian-send')));
    await tester.pumpAndSettle();

    expect(find.text('Enter their name.'), findsOneWidget);
    expect(find.text('Choose how they are related.'), findsOneWidget);
    expect(data.guardianAsks, isEmpty);
  });

  testWidgets("the school's refusal is shown as it said it", (tester) async {
    final data = FakeFamilyRepository()
      ..failGuardianAskWith = const Failure(
        code: 'GUARDIAN_PROBLEM',
        message: 'This person is already a guardian of your child.',
      );
    await pumpFamilyApp(tester, data: data, goTo: '/guardians/new');

    await fill(tester);
    await tester.tap(find.byKey(const Key('family-guardian-send')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('family-guardian-problem')), findsOneWidget);
    expect(find.text('This person is already a guardian of your child.'), findsOneWidget);
  });

  testWidgets("earlier requests show the school's answer", (tester) async {
    final data = FakeFamilyRepository()
      ..guardianInviteList = const [
        FamilyGuardianInvite(id: 2, name: 'Rohan Sharma', relationship: 'father', status: 'approved'),
        FamilyGuardianInvite(id: 1, name: 'Asha Devi', relationship: 'other', status: 'declined'),
      ];
    await pumpFamilyApp(tester, data: data, goTo: '/guardians/new');
    // Each text field has its own Scrollable; the page's list is the first.
    await tester.scrollUntilVisible(
      find.byKey(const Key('family-guardian-invite-1')),
      200,
      scrollable: find.byType(Scrollable).first,
    );

    expect(find.text('Approved - the school will give them a set-up letter'), findsOneWidget);
    expect(find.text('Declined by the school'), findsOneWidget);
  });
}

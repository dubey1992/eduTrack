import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/guardians/data/guardian_repository.dart';
import 'package:edutrack_app/features/guardians/data/models/guardian_link.dart';
import 'package:edutrack_app/features/guardians/presentation/family_access_dialog.dart';
import 'package:edutrack_app/features/guardians/presentation/guardian_form_dialog.dart';
import 'package:edutrack_app/features/guardians/presentation/guardians_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_guardian_repository.dart';

Widget _host(FakeGuardianRepository fake, Widget dialog) {
  return ProviderScope(
    overrides: [guardianRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => Center(
            child: ElevatedButton(
              onPressed: () => showDialog<void>(context: context, builder: (_) => dialog),
              child: const Text('Open'),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> _open(WidgetTester tester, FakeGuardianRepository fake, Widget dialog) async {
  tester.view.physicalSize = const Size(1400, 1100);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  await tester.pumpWidget(_host(fake, dialog));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

/// The school office's side of guardians (docs/parent-student-app.md, F0).
void main() {
  group('the guardians of a student', () {
    testWidgets('lists each guardian, the primary contact marked', (tester) async {
      final fake = FakeGuardianRepository(
        links: [
          guardianLink(),
          guardianLink(id: 2, name: 'Rohit Sharma', isPrimary: false, relationship: GuardianRelationship.father),
        ],
      );
      await _open(tester, fake, const GuardiansDialog(studentId: 7, studentName: 'Aarav Sharma'));

      expect(find.text('Guardians · Aarav Sharma'), findsOneWidget);
      expect(find.text('Meera Sharma'), findsOneWidget);
      expect(find.text('Rohit Sharma'), findsOneWidget);
      expect(find.text('Primary contact'), findsOneWidget);
    });

    testWidgets('says when a guardian is also a sibling\'s', (tester) async {
      await _open(
        tester,
        FakeGuardianRepository(links: [guardianLink(children: 2)]),
        const GuardiansDialog(studentId: 7, studentName: 'Aarav Sharma'),
      );

      expect(find.textContaining('Guardian of 2 students here'), findsOneWidget);
    });

    testWidgets('an empty list says what to do', (tester) async {
      await _open(
        tester,
        FakeGuardianRepository(links: []),
        const GuardiansDialog(studentId: 7, studentName: 'Aarav Sharma'),
      );

      expect(find.textContaining('No guardian on record yet'), findsOneWidget);
    });

    testWidgets('a failure to load offers a retry', (tester) async {
      final fake = FakeGuardianRepository(
        failListWith: const Failure(code: 'NETWORK_ERROR', message: 'No connection.'),
      );
      await _open(tester, fake, const GuardiansDialog(studentId: 7, studentName: 'Aarav Sharma'));

      expect(find.text('No connection.'), findsOneWidget);

      fake.failListWith = null;
      await tester.tap(find.text('Retry'));
      await tester.pumpAndSettle();

      expect(find.text('Meera Sharma'), findsOneWidget);
    });

    testWidgets('removing asks first, and cancelling keeps the guardian', (tester) async {
      final fake = FakeGuardianRepository(
        links: [
          guardianLink(),
          guardianLink(id: 2, name: 'Rohit Sharma', isPrimary: false),
        ],
      );
      await _open(tester, fake, const GuardiansDialog(studentId: 7, studentName: 'Aarav Sharma'));

      await tester.tap(find.byKey(const Key('guardian-remove-2')));
      await tester.pumpAndSettle();
      expect(find.text('Remove Rohit Sharma?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(fake.unlinked, isEmpty);

      await tester.tap(find.byKey(const Key('guardian-remove-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(fake.unlinked, [2]);
      expect(find.text('Rohit Sharma'), findsNothing);
    });
  });

  group('adding or editing a guardian', () {
    testWidgets('a name is required and an email must look like one', (tester) async {
      final fake = FakeGuardianRepository();
      await _open(tester, fake, const GuardianFormDialog(studentId: 7));

      await tester.enterText(find.byKey(const Key('guardian-email')), 'not-an-email');
      await tester.tap(find.byKey(const Key('guardian-save')));
      await tester.pumpAndSettle();

      expect(find.text('Enter the guardian\'s name.'), findsOneWidget);
      expect(find.text('Enter a valid email address.'), findsOneWidget);
      expect(fake.saved, isEmpty);
    });

    testWidgets('a valid guardian is sent and the dialog closes', (tester) async {
      final fake = FakeGuardianRepository();
      await _open(tester, fake, const GuardianFormDialog(studentId: 7));

      await tester.enterText(find.byKey(const Key('guardian-name')), 'Rohit Sharma');
      await tester.tap(find.byKey(const Key('guardian-save')));
      await tester.pumpAndSettle();

      expect(fake.saved.single['name'], 'Rohit Sharma');
      expect(find.byType(GuardianFormDialog), findsNothing);
    });

    testWidgets('what the server refuses is said on the form', (tester) async {
      final fake = FakeGuardianRepository(
        failSaveWith: const Failure(
          code: 'GUARDIAN_PROBLEM',
          message: 'Another guardian in this school already has that mobile number.',
        ),
      );
      await _open(tester, fake, const GuardianFormDialog(studentId: 7));

      await tester.enterText(find.byKey(const Key('guardian-name')), 'Rohit Sharma');
      await tester.tap(find.byKey(const Key('guardian-save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('already has that mobile number'), findsOneWidget);
      expect(find.byType(GuardianFormDialog), findsOneWidget);
    });

    testWidgets('editing shows the guardian\'s number in the number box, not repeated', (tester) async {
      await _open(tester, FakeGuardianRepository(), GuardianFormDialog(studentId: 7, link: guardianLink()));

      expect(find.widgetWithText(TextField, '9876543210'), findsOneWidget);
      expect(find.textContaining('+91+91'), findsNothing);
    });

    testWidgets('editing a sibling\'s guardian says it changes both records', (tester) async {
      await _open(tester, FakeGuardianRepository(), GuardianFormDialog(studentId: 7, link: guardianLink(children: 2)));

      expect(find.byKey(const Key('guardian-siblings-note')), findsOneWidget);
    });
  });

  group('the Family app sign-in', () {
    testWidgets('no code until consent is noted', (tester) async {
      final fake = FakeGuardianRepository();
      await _open(tester, fake, FamilyAccessDialog(studentId: 7, link: guardianLink()));

      final letter = find.byKey(const Key('family-print-letter'));
      expect(tester.widget<FilledButton>(letter).onPressed, isNull);

      await tester.tap(find.byKey(const Key('family-consent')));
      await tester.pumpAndSettle();

      expect(tester.widget<FilledButton>(letter).onPressed, isNotNull);
    });

    testWidgets('showing a code shows it once, with its expiry', (tester) async {
      final fake = FakeGuardianRepository();
      await _open(tester, fake, FamilyAccessDialog(studentId: 7, link: guardianLink()));

      await tester.tap(find.byKey(const Key('family-consent')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('family-show-code')));
      await tester.pumpAndSettle();

      expect(find.text('4827 1593'), findsOneWidget);
      expect(find.textContaining('11/14/2026'), findsOneWidget);
      expect(fake.codesIssuedWithConsent, [true]);
    });

    testWidgets('a guardian without a number is told what to add first', (tester) async {
      final fake = FakeGuardianRepository(access: familyAccess(loginMobile: null));
      await _open(tester, fake, FamilyAccessDialog(studentId: 7, link: guardianLink(mobile: null)));

      expect(find.textContaining('Add this guardian\'s mobile number first'), findsOneWidget);
      expect(tester.widget<OutlinedButton>(find.byKey(const Key('family-show-code'))).onPressed, isNull);
    });

    testWidgets('a lost phone is removed after asking', (tester) async {
      final fake = FakeGuardianRepository(
        access: familyAccess(
          hasPasscode: true,
          consentAt: DateTime(2026, 11, 7),
          devices: [FamilyPhone(id: 9, name: 'Pixel 7', lastUsedAt: DateTime(2026, 11, 7), revokedAt: null)],
        ),
      );
      await _open(tester, fake, FamilyAccessDialog(studentId: 7, link: guardianLink(hasFamilyAccount: true)));

      expect(find.text('Signed up'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove phone'));
      await tester.pumpAndSettle();

      expect(fake.phonesRemoved, [9]);
      expect(find.byKey(const Key('family-phone-9')), findsNothing);
    });
  });
}

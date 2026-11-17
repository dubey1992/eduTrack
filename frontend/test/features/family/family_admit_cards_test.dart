import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/family/data/models/family_admit_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart' show pumpFamilyApp;

/// A parent's admit cards in the Family app (docs/examinations.md): only
/// the school's published cards, downloadable when ready, and the school's
/// own sentence - never its reason - when one is not.
const ready = FamilyAdmitCard(
  examinationId: 7,
  name: 'Half-Yearly Examination',
  yearName: '2026-27',
  termName: 'Term 1',
  available: true,
  state: 'ready',
  message: "Your child's admit card is ready.",
  version: 2,
  issuedOn: '11/17/2026',
);

const withheld = FamilyAdmitCard(
  examinationId: 8,
  name: 'Unit Test 3',
  yearName: '2026-27',
  available: false,
  state: 'withheld',
  message: 'This admit card is not available. Please contact the school.',
  version: 1,
  issuedOn: '11/10/2026',
);

void main() {
  testWidgets('says there is nothing yet when the school has published no exam', (tester) async {
    await pumpFamilyApp(tester, goTo: '/admit-cards');

    expect(find.byKey(const Key('family-admit-cards-empty')), findsOneWidget);
  });

  testWidgets('a ready card says its version and hands the PDF to the phone', (tester) async {
    final handed = <String>[];
    final data = FakeFamilyRepository()..admitCardList = const [ready];
    await pumpFamilyApp(tester, data: data, goTo: '/admit-cards', onPdf: (bytes, name) async => handed.add(name));

    expect(find.text('Version 2, issued 11/17/2026'), findsOneWidget);
    await tester.tap(find.byKey(const Key('family-admit-card-download-7')));
    await tester.pumpAndSettle();

    expect(data.pdfsAskedFor.last, startsWith('admit-card:'));
    expect(handed.single, 'admit-card-aarav-half-yearly-examination.pdf');
  });

  testWidgets('a withheld card says to contact the school and offers no download', (tester) async {
    final data = FakeFamilyRepository()..admitCardList = const [ready, withheld];
    await pumpFamilyApp(tester, data: data, goTo: '/admit-cards');

    expect(find.text('This admit card is not available. Please contact the school.'), findsOneWidget);
    expect(find.byKey(const Key('family-admit-card-download-8')), findsNothing);
  });

  testWidgets('a refused download says the school\'s sentence', (tester) async {
    final data = FakeFamilyRepository()
      ..admitCardList = const [ready]
      ..failPdfWith = const Failure(code: 'ADMIT_CARD_UNAVAILABLE', message: 'Withheld by the school.');
    await pumpFamilyApp(tester, data: data, goTo: '/admit-cards');

    await tester.tap(find.byKey(const Key('family-admit-card-download-7')));
    await tester.pumpAndSettle();

    expect(find.text('Withheld by the school.'), findsOneWidget);
  });

  testWidgets('a failed load can be tried again', (tester) async {
    final data = FakeFamilyRepository()..failAdmitCardsWith = Failure.network();
    await pumpFamilyApp(tester, data: data, goTo: '/admit-cards');

    expect(find.byKey(const Key('family-retry')), findsOneWidget);
  });

  testWidgets('More offers the admit cards where the school has class tests', (tester) async {
    await pumpFamilyApp(tester, goTo: '/more');

    expect(find.byKey(const Key('family-more-admit-cards')), findsOneWidget);
  });
}

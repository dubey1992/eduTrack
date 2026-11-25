import 'package:edutrack_app/core/errors/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart';

/// Parent-teacher meetings in the Family app (docs/mobile-apps-review.md,
/// M12, 8.4): pick a free time, move it, cancel it, and what the screen says
/// when there is nothing to pick.
void main() {
  Future<void> pick(WidgetTester tester, int slotId) async {
    final chip = find.byKey(Key('family-meeting-slot-$slotId'));
    await tester.ensureVisible(chip);
    await tester.tap(chip);
    await tester.pumpAndSettle();
  }

  testWidgets('shows the meeting, the teacher and the times', (tester) async {
    await pumpFamilyApp(tester, goTo: '/meetings');

    expect(find.text('Term 1 PTM'), findsOneWidget);
    expect(find.text('12/05/2026 · with Neha Iyer'), findsOneWidget);
    expect(find.text('Please bring the report card.'), findsOneWidget);
    expect(find.text('Pick a time'), findsOneWidget);
    expect(find.text('9:00 AM'), findsOneWidget);
  });

  testWidgets('a free time is booked after the parent confirms', (tester) async {
    final (data, _, _) = await pumpFamilyApp(tester, goTo: '/meetings');

    await pick(tester, 3);
    expect(find.text('Book 9:20 AM?'), findsOneWidget);
    await tester.tap(find.byKey(const Key('family-meeting-confirm')));
    await tester.pumpAndSettle();

    expect(data.booked.single, (meetingId: 7, slotId: 3));
    expect(find.text('Booked for 9:20 AM'), findsOneWidget);
    expect(find.text('Your time: 9:20 AM - 9:30 AM'), findsOneWidget);
  });

  testWidgets('cancelling the dialog books nothing', (tester) async {
    final (data, _, _) = await pumpFamilyApp(tester, goTo: '/meetings');

    await pick(tester, 1);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    expect(data.booked, isEmpty);
  });

  testWidgets('a taken time cannot be picked', (tester) async {
    final (data, _, _) = await pumpFamilyApp(tester, goTo: '/meetings');

    await pick(tester, 2);

    expect(find.text('Book 9:10 AM?'), findsNothing);
    expect(data.booked, isEmpty);
  });

  testWidgets('with a booking, another time is a move and the booking can be cancelled', (tester) async {
    final data = FakeFamilyRepository()..meetingsValue = [FakeFamilyRepository.sampleMeeting(mySlotId: 1)];
    await pumpFamilyApp(tester, data: data, goTo: '/meetings');

    expect(find.text('Or move to another time'), findsOneWidget);
    await pick(tester, 3);
    expect(find.text('Move to 9:20 AM?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byKey(const Key('family-meeting-cancel')));
    await tester.tap(find.byKey(const Key('family-meeting-cancel')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('family-meeting-cancel-confirm')));
    await tester.pumpAndSettle();

    expect(data.cancelled.single, 7);
    expect(find.text('Booking cancelled'), findsOneWidget);
  });

  testWidgets('a time someone else just took is said so', (tester) async {
    final data = FakeFamilyRepository()
      ..failBookingWith = const Failure(
        code: 'PTM_SLOT_TAKEN',
        message: 'Someone has just booked that time. Please choose another.',
      );
    await pumpFamilyApp(tester, data: data, goTo: '/meetings');

    await pick(tester, 1);
    await tester.tap(find.byKey(const Key('family-meeting-confirm')));
    await tester.pumpAndSettle();

    expect(find.text('Someone has just booked that time. Please choose another.'), findsOneWidget);
  });

  testWidgets('on the day nothing can be changed', (tester) async {
    final data = FakeFamilyRepository()..meetingsValue = [FakeFamilyRepository.sampleMeeting(mySlotId: 1, open: false)];
    await pumpFamilyApp(tester, data: data, goTo: '/meetings');

    expect(find.text('Your time: 9:00 AM - 9:10 AM'), findsOneWidget);
    expect(find.text('Booking has closed. To change anything, please call the school.'), findsOneWidget);
    expect(find.byKey(const Key('family-meeting-cancel')), findsNothing);
    expect(find.byKey(const Key('family-meeting-slot-3')), findsNothing);
  });

  testWidgets('no meetings ahead', (tester) async {
    final data = FakeFamilyRepository()..meetingsValue = [];
    await pumpFamilyApp(tester, data: data, goTo: '/meetings');

    expect(find.text('No meetings ahead'), findsOneWidget);
  });

  testWidgets('More is the way in', (tester) async {
    await pumpFamilyApp(tester, goTo: '/more');
    await revealOnMore(tester, find.byKey(const Key('family-more-meetings')));
    await tester.tap(find.byKey(const Key('family-more-meetings')));
    await tester.pumpAndSettle();

    expect(find.text('Term 1 PTM'), findsOneWidget);
  });
}

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import 'family_app_test.dart';

/// "Please call me" and replies to notices in the Family app
/// (docs/parent-student-app.md, F5).
void main() {
  group('asking the school to call', () {
    Future<void> send(WidgetTester tester) async {
      await tester.ensureVisible(find.byKey(const Key('family-call-send')));
      await tester.tap(find.byKey(const Key('family-call-send')));
      await tester.pumpAndSettle();
    }

    testWidgets('to the class teacher, with a good time, and the parent is told', (tester) async {
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/call-requests');

      await tester.enterText(find.byKey(const Key('family-call-reason')), 'About his reading at home.');
      await tester.enterText(find.byKey(const Key('family-call-time')), 'After 5 pm');
      await send(tester);

      expect(data.callsAsked.single, (toOffice: false, reason: 'About his reading at home.', time: 'After 5 pm'));
      expect(find.text('Sent. The class teacher will call you.'), findsOneWidget);
    });

    testWidgets('to the school office instead', (tester) async {
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/call-requests');

      await tester.tap(find.text('School office'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('family-call-reason')), 'A question about the fees.');
      await send(tester);

      expect(data.callsAsked.single.toOffice, isTrue);
    });

    testWidgets('a reason is asked for before anything is sent', (tester) async {
      final (data, _, _) = await pumpFamilyApp(tester, goTo: '/call-requests');

      await send(tester);

      expect(find.text('Please say a little about what it is.'), findsOneWidget);
      expect(data.callsAsked, isEmpty);
    });

    testWidgets('a request already open is answered, not doubled', (tester) async {
      final data = FakeFamilyRepository()
        ..failCallWith = const Failure(
          code: 'CALL_REQUEST_OPEN',
          message: "You've already asked the class teacher to call - they will ring you.",
        );
      await pumpFamilyApp(tester, data: data, goTo: '/call-requests');

      await tester.enterText(find.byKey(const Key('family-call-reason')), 'About the trip.');
      await send(tester);

      expect(find.byKey(const Key('family-call-problem')), findsOneWidget);
    });

    testWidgets('earlier requests show whether the school has called', (tester) async {
      await pumpFamilyApp(tester, goTo: '/call-requests');
      await tester.ensureVisible(find.byKey(const Key('family-call-31')));

      expect(
        find.descendant(of: find.byKey(const Key('family-call-31')), matching: find.text('Called')),
        findsOneWidget,
      );
    });

    testWidgets('More is the way in', (tester) async {
      await pumpFamilyApp(tester, goTo: '/more');
      await revealOnMore(tester, find.byKey(const Key('family-more-call')));

      await tester.tap(find.byKey(const Key('family-more-call')));
      await tester.pumpAndSettle();

      expect(find.text('Ask the school to call you'), findsOneWidget);
    });
  });

  group('a notice that asks', () {
    FakeFamilyRepository asking({bool open = true, bool? answer}) => FakeFamilyRepository(
      notices: [
        familyNotice(
          id: 5,
          reply: tripQuestion(open: open, answer: answer),
        ),
      ],
    );

    testWidgets('is marked as needing an answer in the list', (tester) async {
      await pumpFamilyApp(tester, data: asking(), goTo: '/notices');

      expect(find.text('Answer needed'), findsOneWidget);
    });

    testWidgets('a Yes is sent for the child, and shown', (tester) async {
      final data = asking();
      await pumpFamilyApp(tester, data: data, goTo: '/notices');

      await tester.tap(find.byKey(const Key('family-notice-5')));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const Key('family-reply-note')), 'Packed lunch');
      await tester.tap(find.byKey(Key('family-reply-yes-${aarav.id}')));
      await tester.pumpAndSettle();

      expect(data.replies.single, (noticeId: 5, studentId: aarav.id, answer: true, note: 'Packed lunch'));
      expect(find.text('Aarav: Yes'), findsOneWidget);
    });

    testWidgets('after the closing day the answer shows but cannot change', (tester) async {
      await pumpFamilyApp(tester, data: asking(open: false, answer: false), goTo: '/notices');

      await tester.tap(find.byKey(const Key('family-notice-5')));
      await tester.pumpAndSettle();

      expect(find.text('Aarav: No'), findsOneWidget);
      expect(find.byKey(Key('family-reply-yes-${aarav.id}')), findsNothing);
      expect(find.textContaining('Answers closed'), findsOneWidget);
    });

    testWidgets('a refused answer says why', (tester) async {
      final data = asking()
        ..failReplyWith = const Failure(
          code: 'REPLIES_CLOSED',
          message: 'Answers for this notice have closed. Please contact the school office.',
        );
      await pumpFamilyApp(tester, data: data, goTo: '/notices');

      await tester.tap(find.byKey(const Key('family-notice-5')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('family-reply-no-${aarav.id}')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Answers for this notice have closed'), findsOneWidget);
    });
  });
}

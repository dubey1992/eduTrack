import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/models/signed_in_session.dart';
import 'package:edutrack_app/features/auth/data/session_repository.dart';
import 'package:edutrack_app/features/auth/presentation/signed_in_devices_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSessionRepository implements SessionRepository {
  FakeSessionRepository(this.sessions, {this.failWith});

  List<SignedInSession> sessions;
  Failure? failWith;
  final signedOut = <int>[];
  int othersCalls = 0;

  @override
  Future<List<SignedInSession>> list() async {
    if (failWith != null) throw failWith!;
    return List.of(sessions);
  }

  @override
  Future<void> signOut(int sessionId) async {
    signedOut.add(sessionId);
    sessions = [
      for (final session in sessions)
        if (session.id != sessionId) session,
    ];
  }

  @override
  Future<int> signOutOthers() async {
    othersCalls++;
    final ended = sessions.where((session) => !session.isCurrent).length;
    sessions = [
      for (final session in sessions)
        if (session.isCurrent) session,
    ];
    return ended;
  }
}

const _here = SignedInSession(
  id: 1,
  device: 'Chrome on Windows',
  signedInLabel: '09/18/2026 9:00 AM',
  lastUsedLabel: '09/18/2026 11:40 AM',
  isCurrent: true,
);
const _phone = SignedInSession(
  id: 2,
  device: 'the app on Android',
  signedInLabel: '09/12/2026 7:30 AM',
  lastUsedLabel: '09/17/2026 4:05 PM',
  isCurrent: false,
);
const _unknown = SignedInSession(
  id: 3,
  device: 'api-token',
  signedInLabel: null,
  lastUsedLabel: null,
  isCurrent: false,
);

Widget wrap(FakeSessionRepository fake) {
  return ProviderScope(
    overrides: [sessionRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => showDialog(context: context, builder: (_) => const SignedInDevicesDialog()),
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
}

Future<void> open(WidgetTester tester, FakeSessionRepository fake) async {
  await tester.pumpWidget(wrap(fake));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('lists every device, marks this one, and says when sessions end', (tester) async {
    await open(tester, FakeSessionRepository([_here, _phone, _unknown]));

    expect(find.text('Chrome on Windows'), findsOneWidget);
    expect(find.text('the app on Android'), findsOneWidget);
    expect(find.text('Unknown device'), findsOneWidget);
    expect(find.text('This device'), findsOneWidget);
    expect(find.textContaining('Last used 09/17/2026 4:05 PM'), findsOneWidget);
    expect(find.textContaining('7 days without use'), findsOneWidget);
    // This device is signed out with the header's Log out, not from here.
    expect(find.widgetWithText(TextButton, 'Sign out'), findsNWidgets(2));
  });

  testWidgets('signs one other device out', (tester) async {
    final fake = FakeSessionRepository([_here, _phone]);
    await open(tester, fake);

    await tester.tap(find.widgetWithText(TextButton, 'Sign out'));
    await tester.pumpAndSettle();

    expect(fake.signedOut, [2]);
    expect(find.text('the app on Android'), findsNothing);
    expect(find.text('Signed out of the app on Android.'), findsOneWidget);
  });

  testWidgets('signs every other device out after asking', (tester) async {
    final fake = FakeSessionRepository([_here, _phone, _unknown]);
    await open(tester, fake);

    await tester.tap(find.text('Sign out of all other devices'));
    await tester.pumpAndSettle();
    expect(find.text('Sign out of all other devices?'), findsOneWidget);

    await tester.tap(find.text('Sign out others'));
    await tester.pumpAndSettle();

    expect(fake.othersCalls, 1);
    expect(find.text('Signed out of 2 other devices.'), findsOneWidget);
    expect(find.text('Chrome on Windows'), findsOneWidget);
  });

  testWidgets('offers nothing to sign out when this is the only device', (tester) async {
    await open(tester, FakeSessionRepository([_here]));

    final button = tester.widget<TextButton>(find.widgetWithText(TextButton, 'Sign out of all other devices'));
    expect(button.onPressed, isNull);
  });

  testWidgets('a failure to load says so with a retry', (tester) async {
    await open(
      tester,
      FakeSessionRepository(
        [],
        failWith: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
      ),
    );

    expect(find.text('Something went wrong.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });
}

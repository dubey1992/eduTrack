import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/announcements/data/announcement_repository.dart';
import 'package:edutrack_app/features/announcements/presentation/announcement_screen.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/communication/data/communication_repository.dart';
import 'package:edutrack_app/features/communication/presentation/communication_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/communication_fixtures.dart';
import '../../support/fake_announcement_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_communication_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeCommunicationRepository fake, {required Widget home}) {
  return ProviderScope(
    overrides: [
      communicationRepositoryProvider.overrideWithValue(fake),
      announcementRepositoryProvider.overrideWithValue(FakeAnnouncementRepository()),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: home),
    ),
  );
}

/// The warning that stops "Sent" being read as "delivered".
///
/// Before a real SMS provider is configured, messages are written to a log
/// and recorded as sent. That is fine for a demo and dangerous in a school,
/// so the app has to say so wherever it claims a message went out.
void main() {
  testWidgets('warns on the Communication Center when the gateway sends nothing', (tester) async {
    final fake = FakeCommunicationRepository(
      messages: const [absenceSms, boardingSms],
      providerLabel: 'Demo Gateway',
      providerDelivers: false,
    );

    await tester.pumpWidget(wrap(fake, home: const CommunicationScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No text messages are being delivered'), findsOneWidget);
    expect(find.textContaining('Demo Gateway'), findsWidgets);
    // The point of the warning: it contradicts the word "Sent" on the same
    // screen, so it has to name what actually happened.
    expect(find.textContaining('reached the log'), findsOneWidget);
  });

  testWidgets('warns on the Announcements screen too', (tester) async {
    // Announcements report how many people they reached "by SMS".
    final fake = FakeCommunicationRepository(
      messages: const [absenceSms, boardingSms],
      providerLabel: 'Demo Gateway',
      providerDelivers: false,
    );

    await tester.pumpWidget(wrap(fake, home: const AnnouncementScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No text messages are being delivered'), findsOneWidget);
  });

  testWidgets('stays out of the way once a real gateway is configured', (tester) async {
    final fake = FakeCommunicationRepository(
      messages: const [absenceSms, boardingSms],
      providerLabel: 'Acme SMS',
      providerDelivers: true,
    );

    await tester.pumpWidget(wrap(fake, home: const CommunicationScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No text messages are being delivered'), findsNothing);
  });

  testWidgets('says nothing when the summary could not be loaded', (tester) async {
    // A failed request is not evidence of a demo gateway, and crying wolf
    // would train people to ignore the warning that matters.
    final fake = FakeCommunicationRepository(
      messages: const [absenceSms, boardingSms],
      providerDelivers: false,
      failWith: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
    );

    await tester.pumpWidget(wrap(fake, home: const CommunicationScreen()));
    await tester.pumpAndSettle();

    expect(find.text('No text messages are being delivered'), findsNothing);
  });
}

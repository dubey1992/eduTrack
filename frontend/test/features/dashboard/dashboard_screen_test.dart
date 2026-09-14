import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/dashboard/presentation/dashboard_screen.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_dashboard_repository.dart';
import '../../support/fake_school_repository.dart';

const _admin = AuthenticatedUser(id: 2, name: 'Anita Sharma', email: 'anita@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeDashboardRepository fake, {AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    overrides: [
      dashboardRepositoryProvider.overrideWithValue(fake),
      schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository()),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: DashboardScreen()),
    ),
  );
}

/// Phase 18's landing screen.
///
/// The server decides which figures a role gets, so these check that whatever
/// arrives is rendered honestly - particularly the two states that are easy to
/// misread: a day with no register, and a day the school was shut.
void main() {
  testWidgets('shows the cards the server sent', (tester) async {
    await tester.pumpWidget(wrap(FakeDashboardRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Students'), findsOneWidget);
    expect(find.text('842'), findsOneWidget);
    expect(find.text('Attendance today'), findsOneWidget);
    expect(find.text('94.8%'), findsOneWidget);
  });

  testWidgets('lists what needs attention', (tester) async {
    await tester.pumpWidget(wrap(FakeDashboardRepository()));
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
    expect(find.text('No attendance has been marked yet today.'), findsOneWidget);
  });

  testWidgets('says the school is closed rather than showing an empty day', (tester) async {
    // On a holiday "nothing marked" is the expected state, not a lapse - and
    // the banner has to say so or somebody will go chasing it.
    await tester.pumpWidget(wrap(FakeDashboardRepository(dashboard: holidayDashboard)));
    await tester.pumpAndSettle();

    expect(find.textContaining('Founders Day'), findsOneWidget);
    expect(find.textContaining('the school is closed today'), findsOneWidget);
    expect(find.text('Needs attention'), findsNothing);
  });

  testWidgets('does not claim the school is shut when no school is in scope', (tester) async {
    // A Super Admin across seven schools has no single set of opening hours,
    // so "the school is closed today" would be nonsense.
    await tester.pumpWidget(wrap(FakeDashboardRepository(dashboard: platformDashboard)));
    await tester.pumpAndSettle();

    expect(find.textContaining('the school is closed'), findsNothing);
    expect(find.text('Schools'), findsOneWidget);
  });

  testWidgets('draws a day with no register as a dash, never as zero', (tester) async {
    // A zero bar would read as every child being absent.
    await tester.pumpWidget(wrap(FakeDashboardRepository()));
    await tester.pumpAndSettle();

    expect(find.text('95%'), findsOneWidget);
    expect(find.text('71%'), findsOneWidget);
    expect(find.text('-'), findsOneWidget);
    expect(find.text('0%'), findsNothing);
  });

  testWidgets('shows an error with a retry when the figures cannot be loaded', (tester) async {
    final fake = FakeDashboardRepository(
      failWith: const Failure(code: 'SERVER_ERROR', message: 'Something went wrong.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.text('Something went wrong.'), findsOneWidget);

    fake.failWith = null;
    await tester.tap(find.widgetWithText(OutlinedButton, 'Retry'));
    await tester.pumpAndSettle();

    expect(find.text('842'), findsOneWidget);
  });

  testWidgets('refreshing re-reads the figures', (tester) async {
    // They describe today, and a tab left open outlives today.
    final fake = FakeDashboardRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(fake.fetchCalls, 1);

    await tester.tap(find.widgetWithText(OutlinedButton, 'Refresh'));
    await tester.pumpAndSettle();

    expect(fake.fetchCalls, 2);
  });

  testWidgets('offers the reports to a role that has them', (tester) async {
    await tester.pumpWidget(wrap(FakeDashboardRepository()));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Open reports'), findsOneWidget);
  });

  testWidgets('does not offer reports to a teacher', (tester) async {
    const teacher = AuthenticatedUser(id: 9, name: 'Priya', email: 'p@example.com', role: UserRole.teacher);
    await tester.pumpWidget(wrap(FakeDashboardRepository(), actor: teacher));
    await tester.pumpAndSettle();

    expect(find.widgetWithText(FilledButton, 'Open reports'), findsNothing);
  });
}

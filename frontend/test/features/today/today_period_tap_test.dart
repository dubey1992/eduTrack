import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:edutrack_app/features/today/presentation/today_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';

import '../../support/fake_attendance_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_check_in_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

/// The class register's card on Today (docs/teacher-app.md, T2): what the
/// phone knows about it, and where a tap goes.
/// Today's periods (docs/teacher-app.md, T3): a period under way or over
/// opens the report form, a filed one opens its report, one still to come
/// opens nothing.
void main() {
  late InMemoryKeyValueStore store;
  String? opened;

  setUp(() {
    store = InMemoryKeyValueStore();
    opened = null;
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    Widget landing(GoRouterState state) {
      opened = state.uri.toString();
      return const Scaffold(body: Text('opened'));
    }

    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (context, state) => const Scaffold(body: TodayScreen()),
        ),
        GoRoute(path: '/teaching/report', builder: (context, state) => landing(state)),
        GoRoute(path: '/teaching/reports/:id', builder: (context, state) => landing(state)),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
          checkInRepositoryProvider.overrideWithValue(FakeCheckInRepository()),
          keyValueStoreProvider.overrideWithValue(store),
          attendanceRepositoryProvider.overrideWithValue(FakeAttendanceRepository(failSubmitWith: Failure.network())),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, name: 'Meera Joshi')),
          ),
        ],
        child: MaterialApp.router(theme: AppTheme.teacherLight(), routerConfig: router),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> tapPeriod(WidgetTester tester, int id) async {
    await tester.ensureVisible(find.byKey(Key('today-period-$id')));
    await tester.tap(find.byKey(Key('today-period-$id')));
    await tester.pumpAndSettle();
  }

  testWidgets('a period that is over without a report opens the form for it, on the school day', (tester) async {
    await pump(tester);
    expect(find.text('Report owed - tap to file'), findsOneWidget);

    await tapPeriod(tester, 11);

    final uri = Uri.parse(opened!);
    expect(uri.path, '/teaching/report');
    expect(uri.queryParameters, {
      'entry': '11',
      'date': '2026-10-26',
      'class': 'Grade 8 A',
      'subject': 'Mathematics',
      'period': '1',
      'subject_id': '31',
    });
  });

  testWidgets('a period with its report filed opens that report', (tester) async {
    await pump(tester);

    await tapPeriod(tester, 13);

    expect(opened, '/teaching/reports/501');
  });

  testWidgets('a period still to come opens nothing', (tester) async {
    await pump(tester);

    await tapPeriod(tester, 15);

    expect(opened, isNull);
    expect(find.text('opened'), findsNothing);
  });
}

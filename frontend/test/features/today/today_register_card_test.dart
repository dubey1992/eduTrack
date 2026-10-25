import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/attendance/data/attendance_repository.dart';
import 'package:edutrack_app/features/attendance/data/models/attendance_status.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/check_in/data/check_in_repository.dart';
import 'package:edutrack_app/features/my_register/data/models/saved_register.dart';
import 'package:edutrack_app/features/my_register/data/register_store.dart';
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
void main() {
  late InMemoryKeyValueStore store;
  String? opened;

  setUp(() {
    store = InMemoryKeyValueStore();
    opened = null;
  });

  SavedRegister saved({int userId = 1}) => SavedRegister(
    clientId: 'c1',
    userId: userId,
    classSectionId: 81,
    classSection: 'Grade 8 A',
    date: '2026-10-26',
    marks: const {1: AttendanceStatus.present},
    savedAt: DateTime.utc(2026, 10, 26),
  );

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(480, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final router = GoRouter(
      initialLocation: '/today',
      routes: [
        GoRoute(
          path: '/today',
          builder: (context, state) => const Scaffold(body: TodayScreen()),
        ),
        GoRoute(
          path: '/register/:id',
          builder: (context, state) {
            opened = state.uri.toString();
            return const Scaffold(body: Text('register screen'));
          },
        ),
      ],
    );
    addTearDown(router.dispose);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
          checkInRepositoryProvider.overrideWithValue(FakeCheckInRepository()),
          keyValueStoreProvider.overrideWithValue(store),
          // No signal, so a register waiting on the phone stays waiting.
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

  Finder onCard(String text) =>
      find.descendant(of: find.byKey(const Key('today-register-81')), matching: find.text(text));

  testWidgets('tapping the card opens that class register for the school\'s day', (tester) async {
    await pump(tester);

    await tester.tap(find.byKey(const Key('today-register-81')));
    await tester.pumpAndSettle();

    expect(find.text('register screen'), findsOneWidget);
    expect(opened, '/register/81?date=2026-10-26&label=Grade+8+A');
  });

  testWidgets('a register saved on the phone and not yet sent says so', (tester) async {
    await RegisterStore(store).saveWaiting([saved()]);
    await pump(tester);

    expect(onCard('Saved, not sent'), findsOneWidget);
    expect(onCard('Not taken'), findsNothing);
  });

  testWidgets('a register the server turned down says Not sent', (tester) async {
    await RegisterStore(store).saveUnsent([UnsentRegister.of(saved(), 'Attendance has already been submitted.')]);
    await pump(tester);

    expect(onCard('Not sent'), findsOneWidget);
  });
}

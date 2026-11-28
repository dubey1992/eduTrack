import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/connection_status.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/offline_bar.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_teaching/application/staff_outbox.dart';
import 'package:edutrack_app/features/my_teaching/data/outbox.dart';
import 'package:edutrack_app/features/staff_leave/data/staff_leave_repository.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_staff_leave_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

/// The bar above every web page (docs/offline-web.md, O1 and O3).
void main() {
  late FakeStaffLeaveRepository leave;

  setUp(() => leave = FakeStaffLeaveRepository());

  Future<ProviderContainer> pump(WidgetTester tester) async {
    final container = ProviderContainer(
      overrides: [
        offlineWorkProvider.overrideWithValue(true),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        staffLeaveRepositoryProvider.overrideWithValue(leave),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.schoolAdmin, id: 3)),
        ),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: const Scaffold(
            body: Column(
              children: [
                OfflineBar(),
                Expanded(child: Text('the page')),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return container;
  }

  Future<void> keepLeave(ProviderContainer container) => container
      .read(staffOutboxProvider.notifier)
      .keepFromWeb(
        kind: OutboxKind.leave,
        key: 'leave:1',
        label: 'Leave: Casual Leave, 12/01/2026 to 12/01/2026',
        payload: {'leave_type': 'casual', 'start_date': '2026-12-01', 'end_date': '2026-12-01', 'reason': 'Errand'},
      );

  testWidgets('online with nothing waiting it takes no space', (tester) async {
    await pump(tester);

    expect(find.byKey(const Key('offline-bar')), findsNothing);
    expect(find.text('the page'), findsOneWidget);
  });

  testWidgets('offline it says so', (tester) async {
    final container = await pump(tester);

    container.read(connectionStatusProvider.notifier).markOffline();
    await tester.pump();

    expect(find.byKey(const Key('offline-bar')), findsOneWidget);
    expect(find.textContaining('Offline - no connection'), findsOneWidget);
  });

  testWidgets('offline with work saved, it counts it', (tester) async {
    leave.failApplyWith = Failure.network();
    final container = await pump(tester);
    container.read(connectionStatusProvider.notifier).markOffline();

    await keepLeave(container);
    await tester.pump();

    expect(find.text('Offline - 1 saved on this computer, sent when the connection is back.'), findsOneWidget);

    // The line comes back: the next try sends it and the bar goes.
    leave.failApplyWith = null;
    container.read(connectionStatusProvider.notifier).markOnline();
    await tester.pump(StaffOutbox.retryDelays.first);
    await tester.pump();

    expect(leave.lastApplyPayload?['reason'], 'Errand');
    expect(find.byKey(const Key('offline-bar')), findsNothing);
  });

  testWidgets('what the server turned down is listed with its reason, and can be dismissed', (tester) async {
    leave.failApplyWith = const Failure(code: 'LEAVE_OVERLAPS', message: 'You already have leave on these days.');
    final container = await pump(tester);

    await keepLeave(container);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('offline-bar-refused')));
    await tester.pumpAndSettle();

    expect(find.text('Leave: Casual Leave, 12/01/2026 to 12/01/2026'), findsOneWidget);
    expect(find.text('You already have leave on these days.'), findsOneWidget);

    await tester.tap(find.text('Dismiss'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('offline-bar')), findsNothing);
  });
}

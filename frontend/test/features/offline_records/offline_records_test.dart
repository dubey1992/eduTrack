import 'dart:convert';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/connection_status.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/offline_records/application/offline_records_notifier.dart';
import 'package:edutrack_app/features/offline_records/data/offline_records_store.dart';
import 'package:edutrack_app/features/offline_records/data/offline_snapshot.dart';
import 'package:edutrack_app/features/offline_records/presentation/offline_records_views.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

/// The trusted computer's copy of records (docs/offline-web.md, O2) - and
/// the rules that keep it safe: only when trusted and allowed, one person's
/// alone, never older than a week, gone when the school switches it off.
Map<String, dynamic> snapshotJson({DateTime? at}) => {
  'generated_at': (at ?? DateTime.now()).toUtc().toIso8601String(),
  'school': {
    'id': 1,
    'name': 'Green Valley',
    'address': 'Pune',
    'phone': '1',
    'email': 'a@b.c',
    'currency_code': 'INR',
  },
  'classes': [
    {'id': 10, 'name': 'Class 6 A'},
    {'id': 11, 'name': 'Class 6 B'},
  ],
  'students': [
    {
      'id': 1,
      'name': 'Asha Rao',
      'admission_number': 'A-1',
      'roll_number': '1',
      'class_section_id': 10,
      'class_name': 'Class 6 A',
      'guardian_name': 'Ravi Rao',
      'guardian_mobile': '+91 90000 11111',
    },
    {
      'id': 2,
      'name': 'Kabir Das',
      'admission_number': 'A-2',
      'roll_number': '2',
      'class_section_id': 11,
      'class_name': 'Class 6 B',
      'guardian_name': 'Meena Das',
      'guardian_mobile': null,
    },
  ],
  'staff': [
    {
      'id': 5,
      'name': 'Neha Iyer',
      'employee_id': 'EMP-1',
      'department': 'Maths',
      'designation': 'Teacher',
      'mobile': '+91 1',
      'email': 'n@x.y',
    },
  ],
  'dues': {
    '1': [
      {
        'id': 70,
        'academic_year_id': 3,
        'academic_year': '2026-27',
        'fee_head': 'Tuition',
        'label': 'Term 2',
        'kind': 'installment',
        'due_date': '2026-11-10',
        'currency_code': 'INR',
        'balance': '3500.00',
        'is_overdue': true,
      },
    ],
  },
};

class FakeSnapshotApi implements OfflineSnapshotApi {
  Failure? failWith;
  int calls = 0;

  @override
  Future<Map<String, dynamic>> fetch() async {
    calls++;
    if (failWith != null) throw failWith!;
    return snapshotJson();
  }
}

void main() {
  late InMemoryKeyValueStore store;
  late FakeSnapshotApi api;

  setUp(() {
    store = InMemoryKeyValueStore();
    api = FakeSnapshotApi();
  });

  Future<ProviderContainer> signIn({int id = 3, bool allowed = true, bool offlineWork = true}) async {
    final container = ProviderContainer(
      overrides: [
        offlineWorkProvider.overrideWithValue(offlineWork),
        keyValueStoreProvider.overrideWithValue(store),
        offlineSnapshotApiProvider.overrideWithValue(api),
        todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
        authRepositoryProvider.overrideWithValue(
          FakeAuthRepository(
            sessionOnRestore: sessionUser(UserRole.schoolAdmin, id: id, offlineCopies: allowed),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
    await container.read(authNotifierProvider.future);
    container.listen(offlineRecordsProvider, (_, _) {});
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  group('the copy', () {
    test('kept once the person says the computer is trusted', () async {
      final container = await signIn();

      await container.read(offlineRecordsProvider.notifier).setTrusted(true);

      expect(container.read(offlineRecordsProvider).snapshot!.students, hasLength(2));
      expect(store.values['offline.trusted_user'], '3');
      expect(store.values['offline.snapshot'], isNotNull);
    });

    test('never kept unticked - and an earlier copy goes', () async {
      final container = await signIn();
      await container.read(offlineRecordsProvider.notifier).setTrusted(true);

      await container.read(offlineRecordsProvider.notifier).setTrusted(false);

      expect(container.read(offlineRecordsProvider).snapshot, isNull);
      expect(store.values, isEmpty);
    });

    test('never kept where the school switched offline copies off', () async {
      final container = await signIn(allowed: false);

      await container.read(offlineRecordsProvider.notifier).setTrusted(true);

      expect(api.calls, 0);
      expect(store.values, isEmpty);
    });

    test('the school switching it off later wipes what was kept', () async {
      final container = await signIn();
      await container.read(offlineRecordsProvider.notifier).setTrusted(true);

      api.failWith = const Failure(code: 'OFFLINE_COPIES_OFF', message: 'Off.');
      await container.read(offlineRecordsProvider.notifier).refresh();

      expect(container.read(offlineRecordsProvider).snapshot, isNull);
      expect(store.values, isEmpty);
    });

    test("another person signing in on the computer finds nothing, and the copy is wiped", () async {
      store.values['offline.trusted_user'] = '3';
      store.values['offline.snapshot'] = jsonEncode(snapshotJson());

      final container = await signIn(id: 9);

      expect(container.read(offlineRecordsProvider).snapshot, isNull);
      expect(store.values, isEmpty);
    });

    test('the same person finds their copy again', () async {
      store.values['offline.trusted_user'] = '3';
      store.values['offline.snapshot'] = jsonEncode(snapshotJson());

      final container = await signIn();

      expect(container.read(offlineRecordsProvider).snapshot, isNotNull);
    });

    test('a copy older than a week is dropped', () async {
      store.values['offline.trusted_user'] = '3';
      store.values['offline.snapshot'] = jsonEncode(snapshotJson(at: DateTime.now().subtract(const Duration(days: 8))));
      api.failWith = Failure.network();

      final container = await signIn();

      expect(container.read(offlineRecordsProvider).snapshot, isNull);
      expect(store.values['offline.snapshot'], isNull);
    });

    test('off the web nothing is ever kept', () async {
      final container = await signIn(offlineWork: false);

      await container.read(offlineRecordsProvider.notifier).setTrusted(true);

      expect(store.values, isEmpty);
    });

    test('signing out wipes it', () async {
      final container = await signIn();
      await container.read(offlineRecordsProvider.notifier).setTrusted(true);

      await container.read(authNotifierProvider.notifier).logout();

      expect(store.values.keys.where((k) => k.startsWith('offline.')), isEmpty);
    });
  });

  test('a fee line never names its head twice', () {
    OfflineDue due(String head, String label) => OfflineDue.fromJson({
      ...((snapshotJson()['dues'] as Map)['1'] as List).first as Map<String, dynamic>,
      'fee_head': head,
      'label': label,
    });

    expect(due('Tuition', 'Term 2').title, 'Tuition - Term 2');
    expect(due('Tuition Fee', 'Tuition Fee - Quarter 4 (Jan-Mar)').title, 'Tuition Fee - Quarter 4 (Jan-Mar)');
  });

  group('the screens', () {
    final snapshot = OfflineSnapshot.fromJson(snapshotJson());

    Future<void> pump(WidgetTester tester, Widget child) async {
      tester.view.physicalSize = const Size(1200, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: child),
        ),
      );
    }

    testWidgets('students search, filter by class, and open with what they owe', (tester) async {
      await pump(tester, OfflineStudentsView(snapshot: snapshot));

      expect(find.textContaining('the copy kept on this computer'), findsOneWidget);
      expect(find.text('2 of 2'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('offline-search')), 'kabir');
      await tester.pump();
      expect(find.text('1 of 2'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('offline-search')), '');
      await tester.tap(find.text('Class 6 A'));
      await tester.pump();
      expect(find.text('Asha Rao'), findsOneWidget);
      expect(find.text('Kabir Das'), findsNothing);

      await tester.tap(find.byKey(const Key('offline-student-1')));
      await tester.pumpAndSettle();
      expect(find.text('Ravi Rao'), findsOneWidget);
      expect(find.text('Tuition - Term 2'), findsOneWidget);
    });

    testWidgets('staff search', (tester) async {
      await pump(tester, OfflineStaffView(snapshot: snapshot));

      await tester.enterText(find.byKey(const Key('offline-search')), 'maths');
      await tester.pump();

      expect(find.text('Neha Iyer'), findsOneWidget);
    });

    testWidgets('online, the normal screen; offline with a copy, the copy', (tester) async {
      final container = ProviderContainer(
        overrides: [
          offlineWorkProvider.overrideWithValue(true),
          keyValueStoreProvider.overrideWithValue(store),
          offlineSnapshotApiProvider.overrideWithValue(api),
          todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.schoolAdmin, id: 3, offlineCopies: true)),
          ),
        ],
      );
      addTearDown(container.dispose);
      await container.read(authNotifierProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            home: Scaffold(
              body: OfflineAware(online: const Text('the online list'), offline: (s) => const Text('the copy')),
            ),
          ),
        ),
      );
      await container.read(offlineRecordsProvider.notifier).setTrusted(true);
      await tester.pump();
      expect(find.text('the online list'), findsOneWidget);

      container.read(connectionStatusProvider.notifier).markOffline();
      await tester.pump();
      expect(find.text('the copy'), findsOneWidget);

      // The half-hourly refresh timer goes with the container.
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });
}

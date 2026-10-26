import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_inbox/data/my_inbox_repository.dart';
import 'package:edutrack_app/features/push/device_repository.dart';
import 'package:edutrack_app/features/push/push_messaging.dart';
import 'package:edutrack_app/features/push/push_registrar.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_my_inbox_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';

class FakePush implements PushMessaging {
  FakePush({this.allowed = true, this.currentToken = 'tok-1', this.launch});

  bool allowed;
  String? currentToken;
  PushNotice? launch;
  int starts = 0;

  final refreshes = StreamController<String>.broadcast();
  final taps = StreamController<PushNotice>.broadcast();
  final arrivals = StreamController<PushNotice>.broadcast();

  @override
  Future<bool> start() async {
    starts++;
    return allowed;
  }

  @override
  Future<String?> token() async => currentToken;

  @override
  Stream<String> get tokenRefreshes => refreshes.stream;

  @override
  Stream<PushNotice> get opened => taps.stream;

  @override
  Future<PushNotice?> launchedBy() async => launch;

  @override
  Stream<PushNotice> get received => arrivals.stream;
}

class FakeDevices implements DeviceRepository {
  final registered = <(String, String)>[];
  final forgotten = <String>[];
  Failure? failRegisterWith;
  Failure? failForgetWith;

  @override
  Future<void> register(String token, {required String app}) async {
    if (failRegisterWith != null) throw failRegisterWith!;
    registered.add((token, app));
  }

  @override
  Future<void> forget(String token) async {
    if (failForgetWith != null) throw failForgetWith!;
    forgotten.add(token);
  }
}

/// Push in the School365ai app (docs/teacher-app.md, T6), with Firebase and
/// the server replaced by fakes.
void main() {
  late FakePush push;
  late FakeDevices devices;
  late List<String> opened;

  setUp(() {
    push = FakePush();
    devices = FakeDevices();
    opened = [];
  });

  Future<void> pump(WidgetTester tester, {bool signedIn = true}) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushMessagingProvider.overrideWithValue(push),
          deviceRepositoryProvider.overrideWithValue(devices),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          myInboxRepositoryProvider.overrideWithValue(FakeMyInboxRepository()),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: signedIn ? sessionUser(UserRole.teacher, id: 7) : null),
          ),
        ],
        child: MaterialApp(
          home: PushRegistrar(
            app: 'staff',
            onOpen: opened.add,
            child: const Scaffold(body: Text('the app')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('signed in and allowed: this phone is registered for the staff app', (tester) async {
    await pump(tester);

    expect(devices.registered, [('tok-1', 'staff')]);
  });

  testWidgets('permission refused: nothing is registered', (tester) async {
    push.allowed = false;
    await pump(tester);

    expect(devices.registered, isEmpty);
  });

  testWidgets('signed out: push is not even started', (tester) async {
    await pump(tester, signedIn: false);

    expect(push.starts, 0);
    expect(devices.registered, isEmpty);
  });

  testWidgets('a build without Firebase does nothing at all', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          deviceRepositoryProvider.overrideWithValue(devices),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, id: 7)),
          ),
        ],
        child: MaterialApp(
          home: PushRegistrar(app: 'staff', onOpen: opened.add, child: const Text('the app')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(devices.registered, isEmpty);
    expect(find.text('the app'), findsOneWidget);
  });

  testWidgets('a new token from Firebase is registered too', (tester) async {
    await pump(tester);

    push.refreshes.add('tok-2');
    await tester.pumpAndSettle();

    expect(devices.registered.last, ('tok-2', 'staff'));
  });

  testWidgets('a registration the server refuses does not stop the app', (tester) async {
    devices.failRegisterWith = Failure.network();
    await pump(tester);

    expect(find.text('the app'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a tapped notification opens what it is about', (tester) async {
    await pump(tester);

    push.taps.add(const PushNotice(title: 'Leave approved', body: '...', route: '/leave'));
    await tester.pumpAndSettle();

    expect(opened, ['/leave']);
  });

  testWidgets('an address the app does not know opens the inbox instead', (tester) async {
    await pump(tester);

    push.taps.add(const PushNotice(title: 'x', body: 'y', route: '/payroll/admin'));
    await tester.pumpAndSettle();

    expect(opened, ['/inbox']);
  });

  testWidgets('a notification that opened the app from closed is followed', (tester) async {
    push.launch = const PushNotice(title: 'Report reviewed', body: '...', route: '/teaching');
    await pump(tester);

    expect(opened, ['/teaching']);
  });

  testWidgets('one arriving with the app open is shown, with Open', (tester) async {
    await pump(tester);

    push.arrivals.add(const PushNotice(title: 'Sports day', body: 'Friday, all classes', route: '/inbox'));
    await tester.pumpAndSettle();

    expect(find.text('Sports day: Friday, all classes'), findsOneWidget);
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(opened, ['/inbox']);
  });

  group('signing out', () {
    ProviderContainer phone() {
      final container = ProviderContainer(
        overrides: [
          deviceRepositoryProvider.overrideWithValue(devices),
          keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(sessionOnRestore: sessionUser(UserRole.teacher, id: 7)),
          ),
        ],
      );
      addTearDown(container.dispose);
      return container;
    }

    test('takes this phone back from the server', () async {
      final container = phone();
      await container.read(authNotifierProvider.future);
      await container.read(pushRegistrationProvider).register('tok-1', app: 'staff');

      await container.read(authNotifierProvider.notifier).logout();

      expect(devices.forgotten, ['tok-1']);
      expect(container.read(pushRegistrationProvider).token, isNull);
      expect(container.read(authNotifierProvider).value, isNull);
    });

    test('signs out even when the server cannot be reached', () async {
      devices.failForgetWith = Failure.network();
      final container = phone();
      await container.read(authNotifierProvider.future);
      await container.read(pushRegistrationProvider).register('tok-1', app: 'staff');

      await container.read(authNotifierProvider.notifier).logout();

      expect(container.read(authNotifierProvider).value, isNull);
    });

    test('with no phone registered, nothing is sent', () async {
      final container = phone();
      await container.read(authNotifierProvider.future);

      await container.read(authNotifierProvider.notifier).logout();

      expect(devices.forgotten, isEmpty);
    });
  });

  test('the platform is named the way the server expects', () {
    expect(['android', 'ios', 'web'], contains(DeviceRepository.platformName));
  });
}

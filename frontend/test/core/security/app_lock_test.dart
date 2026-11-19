import 'package:edutrack_app/core/security/app_lock.dart';
import 'package:edutrack_app/core/security/app_lock_gate.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/in_memory_key_value_store.dart';

/// A phone's fingerprint, as the test decides it.
class FakeDeviceUnlock implements DeviceUnlock {
  FakeDeviceUnlock({this.canLock = true, this.passes = true});

  bool canLock;
  bool passes;
  final List<String> asked = [];

  /// Runs while the prompt is up - the phone's dialog can background the app.
  void Function()? whilePrompting;

  @override
  Future<bool> available() async => canLock;

  @override
  Future<bool> unlock(String reason) async {
    asked.add(reason);
    whilePrompting?.call();
    return passes;
  }
}

/// The app lock (docs/mobile-apps-review.md, 4.4).
void main() {
  late InMemoryKeyValueStore phone;
  late FakeDeviceUnlock device;
  late DateTime now;

  setUp(() {
    phone = InMemoryKeyValueStore();
    device = FakeDeviceUnlock();
    now = DateTime(2026, 11, 19, 9);
  });

  List<Override> overrides() => [
    keyValueStoreProvider.overrideWithValue(phone),
    deviceUnlockProvider.overrideWithValue(device),
    appLockClockProvider.overrideWithValue(() => now),
  ];

  Future<ProviderContainer> started() async {
    final container = ProviderContainer(overrides: overrides());
    addTearDown(container.dispose);
    container.read(appLockProvider);
    await Future<void>.delayed(Duration.zero);
    return container;
  }

  group('the rules', () {
    test('off at first, and nothing is locked', () async {
      final lock = (await started()).read(appLockProvider);

      expect((lock.loaded, lock.enabled, lock.offered, lock.locked), (true, false, false, false));
    });

    test('turned on only after the phone shows it is its owner, and kept on the phone', () async {
      final container = await started();

      expect(await container.read(appLockProvider.notifier).turnOn(), isNull);

      expect(device.asked, ['Confirm it is you to lock School365ai']);
      expect(container.read(appLockProvider).enabled, isTrue);
      expect(phone.values['app_lock.enabled'], 'yes');
    });

    test('a phone with no screen lock is told to set one up first', () async {
      device.canLock = false;
      final container = await started();

      expect(await container.read(appLockProvider.notifier).turnOn(), contains('Set up a fingerprint'));
      expect(container.read(appLockProvider).enabled, isFalse);
      expect(device.asked, isEmpty);
    });

    test('a prompt not passed leaves it off', () async {
      device.passes = false;
      final container = await started();

      expect(await container.read(appLockProvider.notifier).turnOn(), 'The app lock was not turned on.');
      expect(container.read(appLockProvider).enabled, isFalse);
    });

    test('on, the app is locked when it starts', () async {
      phone.values['app_lock.enabled'] = 'yes';

      expect((await started()).read(appLockProvider).locked, isTrue);
    });

    test('locks after five minutes away, not before', () async {
      final container = await started();
      final lock = container.read(appLockProvider.notifier);
      await lock.turnOn();

      lock.wentToBackground();
      now = now.add(const Duration(minutes: 4, seconds: 59));
      lock.cameBack();
      expect(container.read(appLockProvider).locked, isFalse);

      lock.wentToBackground();
      now = now.add(AppLockController.lockAfter);
      lock.cameBack();
      expect(container.read(appLockProvider).locked, isTrue);
    });

    test('off, time away locks nothing', () async {
      final container = await started();
      final lock = container.read(appLockProvider.notifier)..wentToBackground();
      now = now.add(const Duration(hours: 1));
      lock.cameBack();

      expect(container.read(appLockProvider).locked, isFalse);
    });

    test('the phone\'s own prompt sending the app away does not count as leaving', () async {
      phone.values['app_lock.enabled'] = 'yes';
      final container = await started();
      final lock = container.read(appLockProvider.notifier);
      device.whilePrompting = () {
        lock.wentToBackground();
        now = now.add(const Duration(minutes: 10));
        lock.cameBack();
      };

      expect(await lock.unlock(), isTrue);
      expect(container.read(appLockProvider).locked, isFalse);
    });

    test('a failed unlock stays locked', () async {
      phone.values['app_lock.enabled'] = 'yes';
      device.passes = false;
      final container = await started();

      expect(await container.read(appLockProvider.notifier).unlock(), isFalse);
      expect(container.read(appLockProvider).locked, isTrue);
    });

    test('a phone whose screen lock was removed is not shut out: the lock switches itself off', () async {
      phone.values['app_lock.enabled'] = 'yes';
      device.canLock = false;
      final container = await started();

      expect(await container.read(appLockProvider.notifier).unlock(), isTrue);
      expect(container.read(appLockProvider).enabled, isFalse);
      expect(phone.values.containsKey('app_lock.enabled'), isFalse);
    });

    test('signing out forgets the choice and the offer', () async {
      phone.values
        ..['app_lock.enabled'] = 'yes'
        ..['app_lock.offered'] = 'yes';
      final container = await started();

      await container.read(appLockProvider.notifier).forget();

      expect(phone.values, isEmpty);
      expect(container.read(appLockProvider).locked, isFalse);
    });
  });

  group('on screen', () {
    Future<void> pump(WidgetTester tester, {bool signedIn = true}) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: overrides(),
          child: MaterialApp(
            builder: (context, child) => AppLockGate(signedIn: signedIn, child: child!),
            home: const Scaffold(body: Column(children: [Text('Payslip'), AppLockSwitch()])),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('locked, the app is covered and the phone asks at once; passed, it opens', (tester) async {
      phone.values['app_lock.enabled'] = 'yes';
      device.passes = false;
      await pump(tester);

      expect(find.byKey(const Key('app-lock-screen')), findsOneWidget);
      expect(device.asked, ['Unlock School365ai'], reason: 'asked without a tap');
      expect(find.byKey(const Key('app-lock-failed')), findsOneWidget);

      device.passes = true;
      await tester.tap(find.byKey(const Key('app-lock-unlock')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
      expect(find.text('Payslip'), findsOneWidget);
    });

    testWidgets('nobody signed in: no lock and no offer', (tester) async {
      phone.values['app_lock.enabled'] = 'yes';
      await pump(tester, signedIn: false);

      expect(find.byKey(const Key('app-lock-screen')), findsNothing);
      expect(find.byKey(const Key('app-lock-offer')), findsNothing);
    });

    testWidgets('after signing in it is offered once; Not now is remembered', (tester) async {
      await pump(tester);
      expect(find.byKey(const Key('app-lock-offer')), findsOneWidget);

      await tester.tap(find.byKey(const Key('app-lock-not-now')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app-lock-offer')), findsNothing);
      expect(phone.values['app_lock.offered'], 'yes');
    });

    testWidgets('Turn on from the offer turns it on', (tester) async {
      await pump(tester);

      await tester.tap(find.byKey(const Key('app-lock-turn-on')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app-lock-offer')), findsNothing);
      expect(phone.values['app_lock.enabled'], 'yes');
      expect(tester.widget<SwitchListTile>(find.byKey(const Key('app-lock-switch'))).value, isTrue);
    });

    testWidgets('a phone that cannot lock is offered nothing and shows no switch', (tester) async {
      device.canLock = false;
      await pump(tester);

      expect(find.byKey(const Key('app-lock-offer')), findsNothing);
      expect(find.byKey(const Key('app-lock-switch')), findsNothing);
    });

    testWidgets('the switch turns it off again', (tester) async {
      phone.values
        ..['app_lock.enabled'] = 'yes'
        ..['app_lock.offered'] = 'yes';
      await pump(tester);

      await tester.tap(find.byKey(const Key('app-lock-switch')));
      await tester.pumpAndSettle();

      expect(phone.values.containsKey('app_lock.enabled'), isFalse);
    });

    testWidgets('the switch says why it did not turn on', (tester) async {
      phone.values['app_lock.offered'] = 'yes';
      device.passes = false;
      await pump(tester);

      await tester.tap(find.byKey(const Key('app-lock-switch')));
      await tester.pumpAndSettle();

      expect(find.text('The app lock was not turned on.'), findsOneWidget);
    });

    testWidgets('five minutes in the background locks it', (tester) async {
      phone.values
        ..['app_lock.enabled'] = 'yes'
        ..['app_lock.offered'] = 'yes';
      await pump(tester);
      expect(find.byKey(const Key('app-lock-screen')), findsNothing, reason: 'unlocked at start by the prompt');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
      now = now.add(const Duration(minutes: 6));
      device.passes = false;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('app-lock-screen')), findsOneWidget);
    });

    testWidgets('signing out forgets it', (tester) async {
      phone.values
        ..['app_lock.enabled'] = 'yes'
        ..['app_lock.offered'] = 'yes';
      await pump(tester);
      await pump(tester, signedIn: false);

      expect(phone.values, isEmpty);
    });
  });
}

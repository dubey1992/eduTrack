import 'package:edutrack_app/features/family/data/family_auth_repository.dart';
import 'package:edutrack_app/features/family/data/family_repository.dart';
import 'package:edutrack_app/features/family/presentation/family_push_registrar.dart';
import 'package:edutrack_app/features/push/device_repository.dart';
import 'package:edutrack_app/features/push/push_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_family_repositories.dart';
import '../push/push_registrar_test.dart' show FakeDevices, FakePush;

/// A tapped Family notification opens the screen it is about
/// (docs/mobile-apps-review.md, 5.2).
void main() {
  late FakePush push;
  late List<String> opened;

  setUp(() {
    push = FakePush();
    opened = [];
  });

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          pushMessagingProvider.overrideWithValue(push),
          deviceRepositoryProvider.overrideWithValue(FakeDevices()),
          familyRepositoryProvider.overrideWithValue(FakeFamilyRepository()),
          familyAuthRepositoryProvider.overrideWithValue(FakeFamilyAuthRepository(account: familyAccount())),
        ],
        child: MaterialApp(
          home: FamilyPushRegistrar(
            onOpen: opened.add,
            child: const Scaffold(body: Text('the app')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  PushNotice notice(String route) => PushNotice(title: 'Fee reminder', body: 'Term 2 is due', route: route);

  testWidgets('a fee reminder opens Fees, a bus alert the Bus tab', (tester) async {
    await pump(tester);

    for (final route in ['/fees', '/bus', '/results', '/attendance']) {
      push.taps.add(notice(route));
      await tester.pump();
    }

    expect(opened, ['/fees', '/bus', '/results', '/attendance']);
  });

  testWidgets('an address the app does not know opens Notices', (tester) async {
    await pump(tester);

    push.taps.add(notice('/payroll/runs/4'));
    await tester.pump();

    expect(opened, ['/notices']);
  });

  testWidgets('a notification that started the app opens its screen', (tester) async {
    push.launch = notice('/fees');
    await pump(tester);

    expect(opened, ['/fees']);
  });

  test('the allow-list holds only Family screens', () {
    expect(safeFamilyPushRoute('/inbox'), '/notices');
    expect(safeFamilyPushRoute('/bus/live'), '/bus/live');
  });
}

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/biometric/data/biometric_repository.dart';
import 'package:edutrack_app/features/biometric/presentation/device_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_biometric_repository.dart';

const _admin = AuthenticatedUser(id: 1, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeBiometricRepository fake, {AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    overrides: [
      biometricRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: DeviceListScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('it lists the devices a school has', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [fakeDevice()])));
    await tester.pumpAndSettle();

    expect(find.text('Front gate'), findsOneWidget);
    expect(find.text('ZK-0001'), findsOneWidget);
    expect(find.text('Reception'), findsOneWidget);
  });

  testWidgets('no devices yet says so', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeBiometricRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No devices registered yet.'), findsOneWidget);
  });

  group('whether a device has ever spoken', () {
    testWidgets('one never heard from says exactly that', (tester) async {
      // Not a blank: a blank reads as "no information", and this is
      // information - it is somebody's next job.
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [fakeDevice()])));
      await tester.pumpAndSettle();

      expect(find.text('Never heard from'), findsOneWidget);
    });

    testWidgets('one that has spoken shows when', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [fakeDevice(lastSeenAt: '2026-10-20T06:30:00Z')])));
      await tester.pumpAndSettle();

      expect(find.text('Never heard from'), findsNothing);
      expect(find.textContaining('10/20/2026'), findsOneWidget);
    });
  });

  testWidgets('searching asks the server', (tester) async {
    useDesktop(tester);
    final fake = FakeBiometricRepository(
      devices: [
        fakeDevice(),
        fakeDevice(id: 2, name: 'Staff room', serial: 'ZK-0002'),
      ],
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Search devices'), 'staff');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(fake.lastQuery, 'staff');
    expect(find.text('Staff room'), findsOneWidget);
    expect(find.text('Front gate'), findsNothing);
  });

  testWidgets('a failure shows its message with a retry', (tester) async {
    useDesktop(tester);
    final fake = FakeBiometricRepository()..failListWith = Failure.network();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
  });

  group('removing one', () {
    testWidgets('asks first, and says what it does not do', (tester) async {
      // Removing it from the register does not change the device itself,
      // and somebody about to press it should know that.
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [fakeDevice()])));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove device?'), findsOneWidget);
      expect(find.textContaining('The device itself is not changed'), findsOneWidget);
    });

    testWidgets('cancelling leaves it alone', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository(devices: [fakeDevice()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(fake.removed, isEmpty);
      expect(find.text('Front gate'), findsOneWidget);
    });

    testWidgets('confirming removes it', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository(devices: [fakeDevice()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(fake.removed, [1]);
    });
  });

  testWidgets('somebody who may not manage the register sees no controls', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(
        FakeBiometricRepository(devices: [fakeDevice()]),
        actor: const AuthenticatedUser(id: 2, name: 'Teacher', email: 'teacher@example.com', role: UserRole.teacher),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Front gate'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Register Device'), findsNothing);
    expect(find.byTooltip('Remove'), findsNothing);
  });
}

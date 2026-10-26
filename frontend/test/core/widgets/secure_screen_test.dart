import 'package:edutrack_app/core/widgets/secure_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// Payslips and passcode screens are kept out of screenshots while they are
/// open, and only while they are open (docs/security.md, "The phone apps").
void main() {
  const channel = MethodChannel('school365ai/secure_screen');
  late List<Object?> calls;

  setUp(() {
    calls = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call.arguments);
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  final android = TargetPlatformVariant.only(TargetPlatform.android);

  testWidgets('on while a secure screen is open, off when it closes', variant: android, (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SecureScreen(child: Text('Payslip'))));

    expect(SecureScreenGuard.instance.isOn, isTrue);
    expect(calls, [true]);

    await tester.pumpWidget(const MaterialApp(home: Text('Today')));

    expect(SecureScreenGuard.instance.isOn, isFalse);
    expect(calls, [true, false]);
  });

  testWidgets('one secure screen on top of another keeps it on until the last closes', variant: android, (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: SecureScreen(child: SecureScreen(child: Text('Payslip detail'))),
      ),
    );
    expect(calls, [true], reason: 'switched once, not once per screen');

    await tester.pumpWidget(const MaterialApp(home: SecureScreen(child: Text('Payslips'))));
    expect(SecureScreenGuard.instance.isOn, isTrue);
    expect(calls, [true]);

    await tester.pumpWidget(const MaterialApp(home: Text('Today')));
    expect(calls, [true, false]);
  });

  testWidgets(
    'nothing is asked of a platform that is not Android',
    variant: TargetPlatformVariant.only(TargetPlatform.iOS),
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: SecureScreen(child: Text('Payslip'))));
      await tester.pumpWidget(const MaterialApp(home: Text('Today')));

      expect(calls, isEmpty);
    },
  );
}

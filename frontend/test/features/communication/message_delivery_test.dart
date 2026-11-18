import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/communication/data/models/message.dart';
import 'package:edutrack_app/features/communication/presentation/communication_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// What the phone network reported about a message (docs/dashboard.md, D2).

Message _message({String? delivery, String? label, String? error}) {
  return Message.fromJson({
    'id': 7,
    'school_id': 1,
    'event': 'attendance.absent',
    'event_label': 'Student absent',
    'category': 'attendance',
    'channel': 'sms',
    'recipient_name': 'Meera Sharma',
    'recipient_mobile': '+91 9000000000',
    'student_id': null,
    'student_name': null,
    'subject': null,
    'body': 'Aarav was absent today.',
    'status': 'sent',
    'provider': 'twilio',
    'provider_label': 'Twilio',
    'failure_reason': null,
    'sent_at': null,
    'read_at': null,
    'created_at': null,
    'delivery_status': delivery,
    'delivery_status_label': label,
    'delivery_error': error,
  });
}

Future<void> _show(WidgetTester tester, Message message) {
  return tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: MessageStatusCell(message: message)),
    ),
  );
}

void main() {
  test('the report is read from the log row', () {
    final message = _message(delivery: 'undelivered', label: 'Not delivered', error: 'Twilio error 30003');

    expect(
      (message.deliveryStatusLabel, message.deliveryError, message.wasNotDelivered),
      ('Not delivered', 'Twilio error 30003', true),
    );
  });

  testWidgets('a delivered message says so beside its status', (tester) async {
    await _show(tester, _message(delivery: 'delivered', label: 'Delivered'));

    expect(find.byType(MessageStatusBadge), findsOneWidget);
    expect(find.byKey(const Key('delivery-7')), findsOneWidget);
    expect(find.text('Delivered'), findsOneWidget);
  });

  testWidgets('with no report yet, only the status shows - nothing is assumed', (tester) async {
    await _show(tester, _message());

    expect(find.byType(MessageStatusBadge), findsOneWidget);
    expect(find.byKey(const Key('delivery-7')), findsNothing);
  });
}

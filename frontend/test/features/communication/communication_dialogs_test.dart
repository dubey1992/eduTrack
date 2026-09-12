import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/communication/data/communication_repository.dart';
import 'package:edutrack_app/features/communication/data/models/message.dart';
import 'package:edutrack_app/features/communication/presentation/communication_settings_dialog.dart';
import 'package:edutrack_app/features/communication/presentation/message_templates_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/communication_fixtures.dart';
import '../../support/fake_communication_repository.dart';

Widget wrap(FakeCommunicationRepository fake, Widget dialog) {
  return ProviderScope(
    overrides: [communicationRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: Builder(builder: (context) => dialog)),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1400, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

void main() {
  group('MessageTemplatesDialog', () {
    testWidgets('lists every event with its wording and marks the custom ones', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('Marked absent'), findsOneWidget);
      expect(find.text('Boarded the bus'), findsOneWidget);
      expect(find.text(absentTemplate.body), findsOneWidget);
      expect(find.text('Custom'), findsOneWidget);
      // Only the reworded one offers to go back to the shipped text.
      expect(find.widgetWithText(TextButton, 'Use default'), findsOneWidget);
    });

    testWidgets('editing an event saves the new wording', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
      await tester.pumpAndSettle();
      expect(find.text('Edit: Marked absent'), findsOneWidget);
      expect(find.text('{student_name}'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Namaste {guardian_name}, {student_name} was absent.');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {
        'op': 'updateTemplate',
        'event': 'attendance.absent',
        'school_id': 1,
        'body': 'Namaste {guardian_name}, {student_name} was absent.',
      });
      expect(find.text('Marked absent updated.'), findsOneWidget);
    });

    testWidgets('an empty or too-short message is refused before it reaches the server', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), '');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('Enter the message to send.'), findsOneWidget);

      await tester.enterText(find.byType(TextFormField), 'Too short');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();
      expect(find.text('This message is too short to be useful.'), findsOneWidget);

      expect(fake.lastCall, isNull);
    });

    testWidgets('a server rejection is shown inside the edit dialog', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
      await tester.pumpAndSettle();

      fake.failWith = const Failure(
        code: 'VALIDATION_ERROR',
        message: 'This message can only use these placeholders: {student_name}.',
      );
      await tester.enterText(find.byType(TextFormField), 'Owes {fee_amount} rupees to the school.');
      await tester.tap(find.widgetWithText(FilledButton, 'Save'));
      await tester.pumpAndSettle();

      expect(find.text('This message can only use these placeholders: {student_name}.'), findsOneWidget);
      expect(find.text('Edit: Marked absent'), findsOneWidget);
    });

    testWidgets('tapping a placeholder chip appends it to the message', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Edit').first);
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextFormField), 'Hello ');
      await tester.tap(find.widgetWithText(ActionChip, '{student_name}'));
      await tester.pumpAndSettle();

      expect(find.text('Hello {student_name}'), findsOneWidget);
    });

    testWidgets('using the default restores the shipped wording', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(TextButton, 'Use default'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {'op': 'resetTemplate', 'event': 'transport.boarded', 'school_id': 1});
      expect(find.text(boardedTemplate.defaultBody), findsOneWidget);
      expect(find.text('Custom'), findsNothing);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository()
        ..failWith = const Failure(code: 'SERVER_ERROR', message: 'Templates could not be loaded.');
      await tester.pumpWidget(wrap(fake, const MessageTemplatesDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('Templates could not be loaded.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    });
  });

  group('CommunicationSettingsDialog', () {
    testWidgets('shows the current switches and says when they are still defaults', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeCommunicationRepository(), const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('This school is still on the default settings.'), findsOneWidget);
      expect(find.text('Enable parent SMS'), findsOneWidget);
      expect(find.text('Absent only'), findsWidgets);
      expect(find.text('Demo Gateway'), findsWidgets);
      expect(tester.widget<SwitchListTile>(find.widgetWithText(SwitchListTile, 'Transport alerts')).value, isTrue);
    });

    testWidgets('saving sends every switch and confirms', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(SwitchListTile, 'Transport alerts'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(DropdownButtonFormField<AttendanceAlertMode>, 'Absent only'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Present + Absent').last);
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Sender ID (optional)'), 'SUNRIS');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save Settings'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save Settings'));
      await tester.pumpAndSettle();

      expect(fake.lastCall, {
        'op': 'updateSettings',
        'school_id': 1,
        'sms_enabled': true,
        'attendance_alerts': 'both',
        'transport_alerts_enabled': false,
        'leave_alerts_enabled': true,
        'provider': 'log',
        'sender_id': 'SUNRIS',
      });
      expect(find.text('Alert settings saved.'), findsOneWidget);
    });

    testWidgets('a bad sender ID is refused before it reaches the server', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      await tester.enterText(find.widgetWithText(TextFormField, 'Sender ID (optional)'), 'not valid!');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save Settings'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save Settings'));
      await tester.pumpAndSettle();

      expect(find.text('A sender ID can only contain letters, numbers and hyphens.'), findsOneWidget);
      expect(fake.lastCall, isNull);
    });

    testWidgets('a server rejection is shown in the form', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository();
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      fake.failWith = const Failure(code: 'VALIDATION_ERROR', message: 'That SMS gateway is not available.');
      await tester.ensureVisible(find.widgetWithText(FilledButton, 'Save Settings'));
      await tester.tap(find.widgetWithText(FilledButton, 'Save Settings'));
      await tester.pumpAndSettle();

      expect(find.text('That SMS gateway is not available.'), findsOneWidget);
    });

    testWidgets('a load failure offers a retry', (tester) async {
      useDesktop(tester);
      final fake = FakeCommunicationRepository()
        ..failWith = const Failure(code: 'SERVER_ERROR', message: 'Settings could not be loaded.');
      await tester.pumpWidget(wrap(fake, const CommunicationSettingsDialog(schoolId: 1)));
      await tester.pumpAndSettle();

      expect(find.text('Settings could not be loaded.'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
    });
  });
}

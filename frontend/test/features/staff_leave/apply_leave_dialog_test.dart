import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/staff_leave/data/models/leave_status.dart';
import 'package:edutrack_app/features/staff_leave/data/staff_leave_repository.dart';
import 'package:edutrack_app/features/staff_leave/presentation/apply_leave_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_staff_leave_repository.dart';

Widget wrap(FakeStaffLeaveRepository fake) {
  return ProviderScope(
    overrides: [staffLeaveRepositoryProvider.overrideWithValue(fake)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(
        body: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () => showDialog(context: context, builder: (_) => const ApplyLeaveDialog()),
            child: const Text('Open'),
          ),
        ),
      ),
    ),
  );
}

void main() {
  testWidgets('shows a validation error when reason is left empty', (tester) async {
    await tester.pumpWidget(wrap(FakeStaffLeaveRepository()));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    expect(find.text('Reason is required'), findsOneWidget);
  });

  testWidgets('a regular applicant is told the request was submitted for review', (tester) async {
    // applyResultStatus defaults to LeaveStatus.pending - the normal case
    // for anyone but a School Admin applying for their own leave.
    final fake = FakeStaffLeaveRepository();
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Family function');
    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    expect(fake.lastApplyPayload, isNotNull);
    expect(fake.lastApplyPayload!['reason'], 'Family function');
    expect(find.byType(ApplyLeaveDialog), findsNothing);
    expect(find.text('Leave request submitted.'), findsOneWidget);
  });

  testWidgets('a school admin applying for their own leave is told it was auto-approved', (tester) async {
    final fake = FakeStaffLeaveRepository(applyResultStatus: LeaveStatus.approved);
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Family function');
    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    expect(fake.lastApplyPayload, isNotNull);
    expect(find.byType(ApplyLeaveDialog), findsNothing);
    expect(find.text('Leave request approved automatically.'), findsOneWidget);
  });

  testWidgets('shows the failure message and keeps the dialog open on error', (tester) async {
    final fake = FakeStaffLeaveRepository(
      failApplyWith: const Failure(code: 'LEAVE_OVERLAPS_EXISTING', message: 'You already have leave on these dates.'),
    );
    await tester.pumpWidget(wrap(fake));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Reason'), 'Family function');
    await tester.tap(find.text('Submit Request'));
    await tester.pumpAndSettle();

    expect(find.text('You already have leave on these dates.'), findsOneWidget);
    expect(find.byType(ApplyLeaveDialog), findsOneWidget);
  });
}

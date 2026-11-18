import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/module_access.dart';
import 'package:edutrack_app/core/models/permission_level.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/dashboard/presentation/dashboard_links.dart';
import 'package:edutrack_app/features/dashboard/presentation/widgets/dashboard_panels.dart';
import 'package:edutrack_app/features/fees/data/fee_repository.dart';
import 'package:edutrack_app/features/fees/data/models/fees_lock.dart';
import 'package:edutrack_app/features/fees/presentation/widgets/fees_lock_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_fee_repository.dart';
import '../../support/session_users.dart';

/// The fee books' date lock (docs/dashboard.md, D3).

Widget _host(FakeFeeRepository fees, Widget child) {
  return ProviderScope(
    overrides: [feeRepositoryProvider.overrideWithValue(fees)],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: Scaffold(body: child),
    ),
  );
}

Widget _opener(FakeFeeRepository fees) => _host(
  fees,
  Builder(
    builder: (context) => ElevatedButton(onPressed: () => showFeesLockDialog(context), child: const Text('Open')),
  ),
);

Future<void> _open(WidgetTester tester, FakeFeeRepository fees) async {
  await tester.pumpWidget(_opener(fees));
  await tester.tap(find.text('Open'));
  await tester.pumpAndSettle();
}

void main() {
  group('the dialog', () {
    testWidgets('with nothing locked, saving closes the books up to yesterday', (tester) async {
      final fees = FakeFeeRepository();
      await _open(tester, fees);

      expect(find.text('Nothing is locked: any date can still be recorded.'), findsOneWidget);
      expect(find.textContaining('Attendance, exams and everything else are not affected'), findsOneWidget);
      expect(find.text('Close the books up to 09/13/2026'), findsOneWidget);

      await tester.tap(find.byKey(const Key('fees-lock-save')));
      await tester.pumpAndSettle();

      expect(fees.lockSaves.single.until, DateTime(2026, 9, 13));
      expect(find.text('The fee books are closed up to 09/13/2026.'), findsOneWidget);
      expect(find.byType(FeesLockDialog), findsNothing);
    });

    testWidgets('reopening closed days asks for a reason before anything is sent', (tester) async {
      final fees = FakeFeeRepository()..lockedUntil = DateTime(2026, 9, 10);
      await _open(tester, fees);

      expect(find.text('The fee books are closed up to 09/10/2026.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('fees-lock-clear')));
      await tester.pumpAndSettle();

      expect(find.text('Say why closed days are being reopened.'), findsOneWidget);
      expect(fees.lockSaves, isEmpty);

      await tester.enterText(find.byKey(const Key('fees-lock-reason')), 'Receipt entered on the wrong day');
      await tester.tap(find.byKey(const Key('fees-lock-clear')));
      await tester.pumpAndSettle();

      expect(fees.lockSaves.single, (until: null, reason: 'Receipt entered on the wrong day'));
      expect(find.text('The date lock is cleared.'), findsOneWidget);
    });

    testWidgets('the same date again is nothing to save', (tester) async {
      final fees = FakeFeeRepository()..lockedUntil = DateTime(2026, 9, 10);
      await _open(tester, fees);

      final save = tester.widget<FilledButton>(find.byKey(const Key('fees-lock-save')));
      expect(save.onPressed, isNull);
    });

    testWidgets('somebody who may not move it only reads it', (tester) async {
      final fees = FakeFeeRepository()
        ..lockedUntil = DateTime(2026, 9, 10)
        ..lockCanChange = false;
      await _open(tester, fees);

      expect(find.text('Only a School Admin or an Accountant can move the date lock.'), findsOneWidget);
      expect(find.byKey(const Key('fees-lock-save')), findsNothing);
      expect(find.byKey(const Key('fees-lock-clear')), findsNothing);
    });

    testWidgets("the server's refusal is shown and the dialog stays open", (tester) async {
      final fees = FakeFeeRepository()
        ..failLockWith = const Failure(code: 'VALIDATION_ERROR', message: 'The books can only be locked up to today.');
      await _open(tester, fees);

      await tester.tap(find.byKey(const Key('fees-lock-save')));
      await tester.pumpAndSettle();

      expect(find.text('The books can only be locked up to today.'), findsOneWidget);
      expect(find.byType(FeesLockDialog), findsOneWidget);
    });

    testWidgets('a lock that cannot be loaded offers a retry', (tester) async {
      final fees = FakeFeeRepository()
        ..failWith = const Failure(code: 'NETWORK_ERROR', message: 'Could not reach the server.');
      await _open(tester, fees);

      expect(find.text('Could not reach the server.'), findsOneWidget);
      expect(find.text('Retry'), findsOneWidget);
    });
  });

  group('the line above the receipts', () {
    testWidgets('says until when the books are closed', (tester) async {
      final fees = FakeFeeRepository()..lockedUntil = DateTime(2026, 9, 10);
      await tester.pumpWidget(_host(fees, const FeesLockLine()));
      await tester.pumpAndSettle();

      expect(find.text('Fee books closed up to 09/10/2026'), findsOneWidget);
      expect(find.text('Change'), findsOneWidget);
    });

    testWidgets('is not there when nothing is locked and the person cannot lock', (tester) async {
      final fees = FakeFeeRepository()..lockCanChange = false;
      await tester.pumpWidget(_host(fees, const FeesLockLine()));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('fees-lock-line')), findsNothing);
    });
  });

  group('the quick action', () {
    test('only for a School Admin, Group Admin or Accountant who manages fees', () {
      expect(movesDateLock(sessionUser(UserRole.schoolAdmin)), isTrue);
      expect(movesDateLock(sessionUser(UserRole.accountant)), isTrue);
      expect(movesDateLock(sessionUser(UserRole.teacher)), isFalse);
      expect(movesDateLock(sessionUser(UserRole.superAdmin)), isFalse);
      expect(movesDateLock(null), isFalse);
      // The matrix took fees away, or the school switched the module off.
      expect(
        movesDateLock(sessionUser(UserRole.accountant, permissions: {AppModules.fees: PermissionLevel.view})),
        isFalse,
      );
      expect(movesDateLock(sessionUser(UserRole.schoolAdmin, modules: {AppModules.fees: false})), isFalse);
    });

    testWidgets('opens the date lock over the dashboard', (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final fees = FakeFeeRepository();

      await tester.pumpWidget(
        _host(fees, QuickActionsPanel(user: sessionUser(UserRole.accountant), today: DateTime(2026, 9, 14))),
      );
      await tester.tap(find.byKey(const Key('quick-action-date-lock')));
      await tester.pumpAndSettle();

      expect(find.byType(FeesLockDialog), findsOneWidget);
      expect(find.text('Nothing is locked: any date can still be recorded.'), findsOneWidget);
    });
  });

  test('reopening is any earlier date, or clearing', () {
    final lock = FeesLock(
      schoolId: 1,
      lockedUntil: DateTime(2026, 9, 10),
      today: DateTime(2026, 9, 14),
      canChange: true,
    );

    expect(lock.reopens(null), isTrue);
    expect(lock.reopens(DateTime(2026, 9, 1)), isTrue);
    expect(lock.reopens(DateTime(2026, 9, 12)), isFalse);
    expect(
      FeesLock(schoolId: 1, lockedUntil: null, today: DateTime(2026, 9, 14), canChange: true).reopens(null),
      isFalse,
    );
  });
}

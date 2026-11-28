import 'dart:convert';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/connection_status.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/utils/pdf_hand_off.dart';
import 'package:edutrack_app/features/auth/application/auth_notifier.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/my_teaching/application/staff_outbox.dart';
import 'package:edutrack_app/features/my_teaching/data/outbox.dart';
import 'package:edutrack_app/features/offline_fees/application/offline_fee_counter.dart';
import 'package:edutrack_app/features/offline_fees/application/provisional_receipt_pdf.dart';
import 'package:edutrack_app/features/offline_fees/data/offline_fee_payment.dart';
import 'package:edutrack_app/features/offline_fees/data/offline_fees_repository.dart';
import 'package:edutrack_app/features/offline_fees/presentation/offline_fee_counter_view.dart';
import 'package:edutrack_app/features/offline_fees/presentation/offline_payments_screen.dart';
import 'package:edutrack_app/features/offline_records/data/offline_snapshot.dart';
import 'package:edutrack_app/features/today/data/today_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_today_repository.dart';
import '../../support/in_memory_key_value_store.dart';
import '../../support/session_users.dart';
import '../offline_records/offline_records_test.dart' show snapshotJson;

/// Fees taken at the counter while the internet is down (docs/offline-web.md,
/// O4b): numbered provisional receipts, the payment kept and sent, never the
/// same installment twice, and the office settling what could not be receipted.
class FakeOfflineFeesRepository implements OfflineFeesRepository {
  final sent = <Map<String, dynamic>>[];
  final settled = <({int id, String action, Map<String, dynamic> body})>[];
  Failure? failSendWith;
  Failure? failSettleWith;
  List<OfflineFeePayment> listed = [];

  @override
  Future<OfflineFeePayment> send(Map<String, dynamic> payload) async {
    if (failSendWith != null) throw failSendWith!;
    sent.add(payload);
    return payment(status: 'receipted');
  }

  @override
  Future<PaginatedResponse<OfflineFeePayment>> list({
    OfflineFeeStatus? status,
    int? schoolId,
    int page = 1,
    int perPage = 20,
  }) async => PaginatedResponse(
    items: [
      for (final p in listed)
        if (status == null || p.status == status) p,
    ],
    currentPage: 1,
    lastPage: 1,
    total: listed.length,
    perPage: perPage,
  );

  @override
  Future<OfflineFeePayment> keepOnAccount(int id, {String? reason}) async {
    if (failSettleWith != null) throw failSettleWith!;
    settled.add((id: id, action: 'credit', body: {'reason': reason}));
    return payment(status: 'credited', receiptNumber: 'RCPT-2026-27-00009');
  }

  @override
  Future<OfflineFeePayment> handBack(int id, {required String reason, required String mode, String? reference}) async {
    settled.add((id: id, action: 'refund', body: {'reason': reason, 'mode': mode, 'reference': reference}));
    return payment(status: 'refunded');
  }
}

OfflineFeePayment payment({int id = 7, String status = 'to_settle', String? receiptNumber, String? problem}) =>
    OfflineFeePayment.fromJson({
      'id': id,
      'provisional_number': 'P-K7Q2-3',
      'status': status,
      'problem': problem,
      'student': {'id': 1, 'name': 'Asha Rao', 'admission_number': 'A-1'},
      'receipt_date': '2026-11-28',
      'amount': '3500.00',
      'currency_code': 'INR',
      'payment_mode': 'cash',
      'reference': null,
      'taken_by': 'Office',
      'receipt': receiptNumber == null ? null : {'id': 9, 'receipt_number': receiptNumber},
      'settled_by': null,
      'settle_note': null,
      'refund_mode': null,
    });

void main() {
  late InMemoryKeyValueStore store;
  late FakeOfflineFeesRepository fees;
  final snapshot = OfflineSnapshot.fromJson(snapshotJson());
  final asha = snapshot.students.first;
  final term2 = snapshot.duesOf(asha.id).single;

  setUp(() {
    store = InMemoryKeyValueStore();
    fees = FakeOfflineFeesRepository();
  });

  List<Override> overrides({UserRole role = UserRole.accountant, bool offlineWork = true}) => [
    offlineWorkProvider.overrideWithValue(offlineWork),
    keyValueStoreProvider.overrideWithValue(store),
    offlineFeesRepositoryProvider.overrideWithValue(fees),
    todayRepositoryProvider.overrideWithValue(FakeTodayRepository()),
    authRepositoryProvider.overrideWithValue(
      FakeAuthRepository(sessionOnRestore: sessionUser(role, id: 3, name: 'Office Desk')),
    ),
  ];

  Future<ProviderContainer> counter({UserRole role = UserRole.accountant, bool offlineWork = true}) async {
    final container = ProviderContainer(
      overrides: overrides(role: role, offlineWork: offlineWork),
    );
    await container.read(authNotifierProvider.future);
    container.listen(staffOutboxProvider, (_, _) {});
    return container;
  }

  Future<TakenPayment?> take(ProviderContainer container, {double amount = 3500}) => container
      .read(offlineFeeCounterProvider)
      .take(
        snapshot: snapshot,
        student: asha,
        parts: [(due: term2, amount: amount)],
        mode: OfflineFeeMode.cash,
        takenBy: 'Office Desk',
      );

  group('the counter', () {
    testWidgets('numbers each slip for this computer, and the count only goes up', (tester) async {
      fees.failSendWith = Failure.network();
      final container = await counter();

      final first = await take(container, amount: 1000);
      final second = await take(container, amount: 500);

      expect(first!.provisionalNumber, matches(RegExp(r'^P-[A-Z2-9]{4}-1$')));
      final code = first.provisionalNumber.split('-')[1];
      expect(second!.provisionalNumber, 'P-$code-2');

      // A sign-out does not reset the count.
      await container.read(authNotifierProvider.notifier).logout();
      expect(store.values['fee_counter.code'], code);
      expect(store.values['fee_counter.next'], '3');
      container.dispose();
    });

    testWidgets('keeps what the server takes, and sends it once the line is back', (tester) async {
      fees.failSendWith = Failure.network();
      final container = await counter();

      await take(container);
      await tester.pump();
      final kept = container.read(staffOutboxProvider).single;
      expect(kept.kind, OutboxKind.feePayment);
      expect(kept.payload['student_id'], 1);
      expect(kept.payload['amount'], '3500.00');
      expect(kept.payload['payment_mode'], 'cash');
      expect(kept.payload['allocations'], [
        {'due_id': 70, 'amount': '3500.00'},
      ]);
      expect(kept.payload['client_id'], hasLength(32));

      fees.failSendWith = null;
      await tester.pump(StaffOutbox.retryDelays.first);

      expect(fees.sent.single['provisional_number'], kept.payload['provisional_number']);
      expect(container.read(staffOutboxProvider), isEmpty);
      container.dispose();
    });

    testWidgets('a payment the server turns down stays, with its reason', (tester) async {
      fees.failSendWith = const Failure(code: 'VALIDATION_ERROR', message: 'The selected student id is invalid.');
      final container = await counter();

      await take(container);
      await tester.pump();

      expect(container.read(staffOutboxProvider).single.refusal, 'The selected student id is invalid.');
      container.dispose();
    });

    testWidgets('what is waiting to send comes off what is left to take', (tester) async {
      fees.failSendWith = Failure.network();
      final container = await counter();

      await take(container, amount: 1000);
      await tester.pump();

      expect(takenOfflineByDue(container.read(staffOutboxProvider)), {70: 1000.0});
      container.dispose();
    });

    testWidgets('off the web nothing is kept', (tester) async {
      final container = await counter(offlineWork: false);

      expect(await take(container), isNull);
      expect(container.read(staffOutboxProvider), isEmpty);
      container.dispose();
    });

    test('the provisional receipt is a PDF', () async {
      final bytes = await provisionalReceiptPdf(
        TakenPayment(
          provisionalNumber: 'P-K7Q2-3',
          student: asha,
          school: snapshot.school,
          parts: [(due: term2, amount: 3500)],
          mode: OfflineFeeMode.cheque,
          reference: '004512',
          takenAt: DateTime(2026, 11, 28, 10, 5),
          takenBy: 'Office Desk',
        ),
      );

      expect(latin1.decode(bytes.sublist(0, 5)), '%PDF-');
      expect(pdfMoney(3500, 'INR'), 'INR 3,500.00');
    });
  });

  group('taking a payment', () {
    late List<String> handedOff;

    Future<ProviderContainer> pump(WidgetTester tester, {UserRole role = UserRole.accountant}) async {
      tester.view.physicalSize = const Size(1400, 1100);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      handedOff = [];
      final container = ProviderContainer(
        overrides: [
          ...overrides(role: role),
          pdfHandOffProvider.overrideWithValue((bytes, name) async => handedOff.add(name)),
        ],
      );
      await container.read(authNotifierProvider.future);
      fees.failSendWith = Failure.network();
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: Scaffold(body: OfflineFeeCounterView(snapshot: snapshot)),
          ),
        ),
      );
      return container;
    }

    Future<void> open(WidgetTester tester) async {
      await tester.tap(find.byKey(const Key('offline-student-1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('offline-take-payment')));
      await tester.pumpAndSettle();
    }

    testWidgets('a teacher is never offered it', (tester) async {
      final container = await pump(tester, role: UserRole.teacher);

      await tester.tap(find.byKey(const Key('offline-student-1')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('offline-take-payment')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });

    testWidgets('nothing ticked, more than is owed, or a cheque with no number is refused', (tester) async {
      final container = await pump(tester);
      await open(tester);

      await tester.tap(find.byKey(const Key('offline-pay-save')));
      await tester.pump();
      expect(find.text('Tick at least one fee to take.'), findsOneWidget);

      await tester.tap(find.byKey(const Key('offline-pay-due-70')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('offline-pay-amount-70')), '4000');
      await tester.tap(find.byKey(const Key('offline-pay-save')));
      await tester.pump();
      expect(find.textContaining('is owed'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('offline-pay-amount-70')), '3500');
      await tester.tap(find.text('Cheque'));
      await tester.pump();
      await tester.tap(find.byKey(const Key('offline-pay-save')));
      await tester.pump();
      expect(find.text('Enter the cheque number'), findsOneWidget);
      expect(container.read(staffOutboxProvider), isEmpty);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });

    testWidgets('taken: kept to send, numbered, with the provisional receipt to hand over', (tester) async {
      final container = await pump(tester);
      await open(tester);

      await tester.tap(find.byKey(const Key('offline-pay-due-70')));
      await tester.pump();
      await tester.enterText(find.byKey(const Key('offline-pay-amount-70')), '2000');
      await tester.pump();
      expect(find.textContaining('2,000.00'), findsWidgets);
      await tester.tap(find.byKey(const Key('offline-pay-save')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Taken: P-'), findsOneWidget);
      expect(container.read(staffOutboxProvider).single.payload['amount'], '2000.00');

      await tester.tap(find.byKey(const Key('offline-pay-receipt')));
      await tester.pumpAndSettle();
      expect(handedOff.single, startsWith('provisional-receipt-P-'));

      // The same installment again: only what is left can be taken.
      await tester.tap(find.text('Done'));
      await tester.pumpAndSettle();
      await open(tester);
      expect(find.textContaining(RegExp(r'owes INR\s1,500\.00')), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      container.dispose();
    });
  });

  group('settling', () {
    Future<ProviderContainer> pump(WidgetTester tester, {UserRole role = UserRole.accountant}) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      fees.listed = [
        payment(problem: 'Installment "Tuition - Term 2" is already paid.'),
        payment(id: 8, status: 'receipted', receiptNumber: 'RCPT-2026-27-00004'),
      ];
      final container = ProviderContainer(overrides: overrides(role: role));
      await container.read(authNotifierProvider.future);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: OfflinePaymentsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('opens on what is to settle, with why', (tester) async {
      final container = await pump(tester);

      expect(find.byKey(const Key('offline-payment-7')), findsOneWidget);
      expect(find.byKey(const Key('offline-payment-8')), findsNothing);
      expect(find.text('Installment "Tuition - Term 2" is already paid.'), findsOneWidget);

      await tester.tap(find.text('All'));
      await tester.pumpAndSettle();
      expect(find.text('Receipt RCPT-2026-27-00004'), findsOneWidget);
      container.dispose();
    });

    testWidgets('kept on the account', (tester) async {
      final container = await pump(tester);

      await tester.tap(find.byKey(const Key('offline-payment-settle-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settle-save')));
      await tester.pumpAndSettle();

      expect(fees.settled.single.action, 'credit');
      expect(find.textContaining('kept on account as receipt RCPT-2026-27-00009'), findsOneWidget);
      container.dispose();
    });

    testWidgets('handed back needs a reason, and a cheque its number', (tester) async {
      final container = await pump(tester);

      await tester.tap(find.byKey(const Key('offline-payment-settle-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Handed back'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settle-save')));
      await tester.pump();
      expect(find.text('Say why it was handed back'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('settle-reason')), 'Paid twice');
      await tester.tap(find.byKey(const Key('settle-save')));
      await tester.pumpAndSettle();

      expect(fees.settled.single.action, 'refund');
      expect(fees.settled.single.body['mode'], 'cash');
      container.dispose();
    });

    testWidgets("the server's refusal is shown in the dialog", (tester) async {
      fees.failSettleWith = const Failure(code: 'FEES_LOCKED', message: 'The fee books are closed up to 11/28/2026.');
      final container = await pump(tester);

      await tester.tap(find.byKey(const Key('offline-payment-settle-7')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('settle-save')));
      await tester.pumpAndSettle();

      expect(find.text('The fee books are closed up to 11/28/2026.'), findsOneWidget);
      container.dispose();
    });

    testWidgets('a teacher sees no Settle button', (tester) async {
      final container = await pump(tester, role: UserRole.teacher);

      expect(find.byKey(const Key('offline-payment-settle-7')), findsNothing);
      container.dispose();
    });
  });
}

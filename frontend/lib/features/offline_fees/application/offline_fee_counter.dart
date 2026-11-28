import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';
import '../../../core/utils/currency_formatter.dart';
import '../../my_teaching/application/staff_outbox.dart';
import '../../my_teaching/data/outbox.dart';
import '../../offline_records/data/offline_snapshot.dart';

/// How a payment taken offline was paid: cash or a cheque only (D3).
enum OfflineFeeMode {
  cash('cash', 'Cash'),
  cheque('cheque', 'Cheque');

  const OfflineFeeMode(this.wire, this.label);

  final String wire;
  final String label;
}

/// One fee line paid by a payment taken offline.
typedef OfflinePart = ({OfflineDue due, double amount});

/// A payment the counter has just taken - what the provisional receipt prints.
class TakenPayment {
  const TakenPayment({
    required this.provisionalNumber,
    required this.student,
    required this.school,
    required this.parts,
    required this.mode,
    required this.takenAt,
    required this.takenBy,
    this.reference,
    this.note,
  });

  final String provisionalNumber;
  final OfflineStudent student;
  final OfflineSchool school;
  final List<OfflinePart> parts;
  final OfflineFeeMode mode;
  final String? reference;
  final String? note;
  final DateTime takenAt;
  final String takenBy;

  double get total => parts.fold(0, (sum, part) => sum + part.amount);

  String get currencyCode => parts.isEmpty ? school.currencyCode : parts.first.due.currencyCode;
}

final offlineFeeCounterProvider = Provider<OfflineFeeCounter>(
  (ref) => OfflineFeeCounter(ref.watch(keyValueStoreProvider), ref),
);

/// The fee counter while the internet is down (docs/offline-web.md, O4).
///
/// Each computer numbers its provisional receipts `P-<code>-<n>`: a code made
/// once for the computer and kept, and a count that only goes up - so two
/// counters never hand out the same number, and nothing is reused after a
/// sign-out. The payment goes into the outbox, sent when the line is back.
class OfflineFeeCounter {
  OfflineFeeCounter(this._store, this._ref);

  final KeyValueStore _store;
  final Ref _ref;

  // Not under "offline.": these say nothing about anybody, and must outlive
  // a sign-out so a number is never handed out twice.
  static const _codeKey = 'fee_counter.code';
  static const _nextKey = 'fee_counter.next';

  static const _letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  Future<String> _nextNumber() async {
    var code = await _store.read(_codeKey);
    if (code == null) {
      final random = Random.secure();
      code = String.fromCharCodes([for (var i = 0; i < 4; i++) _letters.codeUnitAt(random.nextInt(_letters.length))]);
      await _store.write(_codeKey, code);
    }
    final next = int.tryParse(await _store.read(_nextKey) ?? '') ?? 1;
    await _store.write(_nextKey, '${next + 1}');
    return 'P-$code-$next';
  }

  static String _clientId() {
    final random = Random.secure();
    return [for (var i = 0; i < 16; i++) random.nextInt(256).toRadixString(16).padLeft(2, '0')].join();
  }

  /// Keeps the payment to send. Null when it cannot be kept - off the web,
  /// or with nobody signed in.
  Future<TakenPayment?> take({
    required OfflineSnapshot snapshot,
    required OfflineStudent student,
    required List<OfflinePart> parts,
    required OfflineFeeMode mode,
    required String takenBy,
    String? reference,
    String? note,
  }) async {
    final number = await _nextNumber();
    final clientId = _clientId();
    final now = DateTime.now();
    final taken = TakenPayment(
      provisionalNumber: number,
      student: student,
      school: snapshot.school,
      parts: parts,
      mode: mode,
      reference: reference,
      note: note,
      takenAt: now,
      takenBy: takenBy,
    );
    final day = '${now.year}-${_two(now.month)}-${_two(now.day)}';

    final kept = await _ref
        .read(staffOutboxProvider.notifier)
        .keepFromWeb(
          kind: OutboxKind.feePayment,
          key: OutboxItem.feePaymentKey(clientId),
          label: 'Fee payment $number - ${student.name}, ${formatCurrency(taken.total, taken.currencyCode)}',
          payload: {
            'client_id': clientId,
            'provisional_number': number,
            'taken_at': now.toUtc().toIso8601String(),
            'student_id': student.id,
            'receipt_date': day,
            'amount': taken.total.toStringAsFixed(2),
            'payment_mode': mode.wire,
            'reference': ?reference,
            'note': ?note,
            'allocations': [
              for (final part in parts) {'due_id': part.due.id, 'amount': part.amount.toStringAsFixed(2)},
            ],
          },
        );
    return kept ? taken : null;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');
}

/// What payments still in the outbox have taken off each fee line, so the
/// counter never takes the same installment twice while offline.
Map<int, double> takenOfflineByDue(List<OutboxItem> outbox) {
  final taken = <int, double>{};
  for (final item in outbox) {
    if (item.kind != OutboxKind.feePayment || item.refusal != null) continue;
    for (final part in (item.payload['allocations'] as List? ?? const []).cast<Map<String, dynamic>>()) {
      final id = part['due_id'] as int;
      taken[id] = (taken[id] ?? 0) + double.parse(part['amount'] as String);
    }
  }
  return taken;
}

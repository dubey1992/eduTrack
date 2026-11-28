import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

/// What the outbox carries (docs/mobile-apps-review.md, 2.1).
enum OutboxKind {
  /// A new teaching report: the fields POST /teaching-reports takes.
  report('report'),

  /// A class test's marks: the rows PUT /assessments/{id}/marks takes.
  marks('marks'),

  /// The staff register for a day, marked in the office on the web
  /// (docs/offline-web.md, O3): what POST staff-attendance takes.
  staffRegister('staff_register'),

  /// A leave application from the web: what POST staff-leaves takes.
  leave('leave'),

  /// A notice written on the web: what POST announcements takes. Files are
  /// uploaded online only, so a notice saved offline carries none.
  notice('notice');

  const OutboxKind(this.apiValue);

  final String apiValue;

  static OutboxKind fromApiValue(String value) => OutboxKind.values.firstWhere((kind) => kind.apiValue == value);
}

/// One piece of work saved on the phone because there was no signal, waiting
/// to be sent - or, once the server turned it down, kept with its reason.
class OutboxItem {
  const OutboxItem({
    required this.kind,
    required this.key,
    required this.userId,
    required this.label,
    required this.payload,
    required this.savedAt,
    this.refusal,
  });

  factory OutboxItem.fromJson(Map<String, dynamic> json) => OutboxItem(
    kind: OutboxKind.fromApiValue(json['kind'] as String),
    key: json['key'] as String,
    userId: json['user_id'] as int,
    label: json['label'] as String,
    payload: json['payload'] as Map<String, dynamic>,
    savedAt: DateTime.parse(json['saved_at'] as String),
    refusal: json['refusal'] as String?,
  );

  final OutboxKind kind;

  /// What it is about - one period on one day, or one test. A newer save of
  /// the same thing replaces the older one: the latest marks are the marks.
  final String key;

  /// Who saved it. Only they send it, as with the register.
  final int userId;

  /// In the person's words: "Mathematics, Grade 8 A, period 1".
  final String label;
  final Map<String, dynamic> payload;
  final DateTime savedAt;

  /// Why the server would not take it; null while it is still to be sent.
  final String? refusal;

  OutboxItem refused(String reason) => OutboxItem(
    kind: kind,
    key: key,
    userId: userId,
    label: label,
    payload: payload,
    savedAt: savedAt,
    refusal: reason,
  );

  Map<String, dynamic> toJson() => {
    'kind': kind.apiValue,
    'key': key,
    'user_id': userId,
    'label': label,
    'payload': payload,
    'saved_at': savedAt.toUtc().toIso8601String(),
    if (refusal != null) 'refusal': refusal,
  };

  static String reportKey(int timetableEntryId, String date) => 'report:$timetableEntryId@$date';

  static String marksKey(int assessmentId) => 'marks:$assessmentId';

  static String staffRegisterKey(int? departmentId, String date) => 'staff-register:${departmentId ?? 'all'}@$date';

  /// Every application and notice is its own; a second never replaces the first.
  static String uniqueKey(String kind) => '$kind:${DateTime.now().microsecondsSinceEpoch}';
}

final outboxStoreProvider = Provider<OutboxStore>((ref) => OutboxStore(ref.watch(keyValueStoreProvider)));

/// The outbox on the phone: one list, under one key. Anything unreadable is
/// treated as empty and logged - a corrupt entry must not stop the app.
class OutboxStore {
  OutboxStore(this._store);

  static const _key = 'staff_outbox';

  final KeyValueStore _store;

  Future<List<OutboxItem>> read() async {
    final raw = await _store.read(_key);
    if (raw == null) return const [];

    try {
      return [for (final item in (jsonDecode(raw) as List).cast<Map<String, dynamic>>()) OutboxItem.fromJson(item)];
    } catch (error) {
      debugPrint('Unreadable outbox dropped: $error');
      await _store.delete(_key);
      return const [];
    }
  }

  Future<void> save(List<OutboxItem> items) => _store.write(_key, jsonEncode([for (final i in items) i.toJson()]));
}

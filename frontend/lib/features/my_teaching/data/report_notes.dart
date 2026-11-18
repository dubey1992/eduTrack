import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/storage/key_value_store.dart';

/// What a teaching report says, without the period it is for - a draft, a
/// template, or last time's report copied in.
class ReportWords {
  const ReportWords({required this.topic, this.homework = '', this.remarks = ''});

  factory ReportWords.fromJson(Map<String, dynamic> json) => ReportWords(
    topic: json['topic'] as String? ?? '',
    homework: json['homework'] as String? ?? '',
    remarks: json['remarks'] as String? ?? '',
  );

  final String topic;
  final String homework;
  final String remarks;

  bool get isEmpty => topic.trim().isEmpty && homework.trim().isEmpty && remarks.trim().isEmpty;

  Map<String, dynamic> toJson() => {'topic': topic, 'homework': homework, 'remarks': remarks};
}

final reportNotesProvider = Provider<ReportNotes>((ref) => ReportNotes(ref.watch(keyValueStoreProvider)));

/// The teaching report's helpers kept on this phone, never on the server
/// (docs/mobile-apps-review.md, 1.6):
///
/// - a **draft** per period and day, written as the teacher types, so a
///   call, a dead battery or a missing check-in loses nothing;
/// - **templates** per subject - the lines a teacher writes every week,
///   saved once and filled in with a tap.
///
/// Each kind is one JSON map under one key, so signing out can forget both
/// ([clear]): they are the signed-in teacher's, not the next person's.
class ReportNotes {
  ReportNotes(this._store);

  /// Enough for a subject's usual lessons without the list becoming a search.
  static const maxTemplates = 10;

  static const _draftsKey = 'report_drafts';
  static const _templatesKey = 'report_templates';

  final KeyValueStore _store;

  static String _draftId(int timetableEntryId, String date) => '$timetableEntryId@$date';

  Future<Map<String, dynamic>> _map(String key) async {
    final raw = await _store.read(key);
    if (raw == null) return {};

    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } on FormatException catch (error) {
      // Unreadable notes are notes lost, not a form that fails to open.
      debugPrint('Unreadable $key dropped: $error');
      await _store.delete(key);
      return {};
    }
  }

  Future<ReportWords?> draft(int timetableEntryId, String date) async {
    final found = (await _map(_draftsKey))[_draftId(timetableEntryId, date)];
    return found is Map<String, dynamic> ? ReportWords.fromJson(found) : null;
  }

  /// An empty form forgets the draft rather than keeping an empty one.
  Future<void> saveDraft(int timetableEntryId, String date, ReportWords words) async {
    final drafts = await _map(_draftsKey);
    if (words.isEmpty) {
      drafts.remove(_draftId(timetableEntryId, date));
    } else {
      drafts[_draftId(timetableEntryId, date)] = words.toJson();
    }
    await _store.write(_draftsKey, jsonEncode(drafts));
  }

  Future<void> forgetDraft(int timetableEntryId, String date) =>
      saveDraft(timetableEntryId, date, const ReportWords(topic: ''));

  Future<List<ReportWords>> templates(int subjectId) async {
    final found = (await _map(_templatesKey))['$subjectId'];
    if (found is! List) return const [];

    return [for (final item in found.cast<Map<String, dynamic>>()) ReportWords.fromJson(item)];
  }

  Future<List<ReportWords>> _saveTemplates(int subjectId, List<ReportWords> kept) async {
    final all = await _map(_templatesKey);
    all['$subjectId'] = [for (final template in kept) template.toJson()];
    await _store.write(_templatesKey, jsonEncode(all));
    return kept;
  }

  /// Newest first. Saving the same topic again replaces the older copy, and
  /// the oldest goes once there are [maxTemplates].
  Future<List<ReportWords>> saveTemplate(int subjectId, ReportWords words) async => _saveTemplates(
    subjectId,
    [
      words,
      for (final template in await templates(subjectId))
        if (template.topic.trim() != words.topic.trim()) template,
    ].take(maxTemplates).toList(),
  );

  Future<List<ReportWords>> deleteTemplate(int subjectId, String topic) async => _saveTemplates(subjectId, [
    for (final template in await templates(subjectId))
      if (template.topic != topic) template,
  ]);

  /// On sign-out.
  Future<void> clear() async {
    await _store.delete(_draftsKey);
    await _store.delete(_templatesKey);
  }
}

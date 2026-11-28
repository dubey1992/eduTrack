import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/network/connection_status.dart';
import '../../announcements/data/announcement_repository.dart';
import '../../announcements/data/models/announcement.dart';
import '../../assessments/data/assessment_repository.dart';
import '../../assessments/data/models/assessment_sheet.dart';
import '../../auth/application/auth_notifier.dart';
import '../../offline_fees/data/offline_fees_repository.dart';
import '../../staff_attendance/data/staff_attendance_repository.dart';
import '../../staff_leave/data/models/leave_type.dart';
import '../../staff_leave/data/staff_leave_repository.dart';
import '../../teaching_reports/data/teaching_report_repository.dart';
import '../../today/application/today_notifier.dart';
import '../data/outbox.dart';
import '../data/report_notes.dart';
import 'my_teaching_providers.dart';

final staffOutboxProvider = NotifierProvider<StaffOutbox, List<OutboxItem>>(StaffOutbox.new);

/// Teaching reports and class-test marks saved with no signal, sent when
/// there is some (docs/mobile-apps-review.md, 2.1) - the register's queue
/// (my_register/application/register_queue.dart) for the rest of a
/// teacher's day.
///
/// Saved on the phone before anything else, so a teacher can close the app.
/// Sending starts at once; with no signal it is tried again after 5, 15, 30
/// and then every 60 seconds, on sign-in, and whenever the app comes back to
/// the front (RegisterSender). A report the server already has is done, not
/// a failure. Anything else it refuses - a check-in it wants first, a test
/// published meanwhile - is kept with the server's reason, and a refused
/// report's words go back into its draft, so opening the period shows them.
class StaffOutbox extends Notifier<List<OutboxItem>> {
  static const retryDelays = [
    Duration(seconds: 5),
    Duration(seconds: 15),
    Duration(seconds: 30),
    Duration(seconds: 60),
  ];

  Timer? _retryTimer;
  int _failures = 0;
  bool _sending = false;
  late Future<void> _loaded;

  OutboxStore get _store => ref.read(outboxStoreProvider);

  int? get _me => ref.read(authNotifierProvider).value?.id;

  @override
  List<OutboxItem> build() {
    ref.onDispose(() => _retryTimer?.cancel());
    _loaded = _load();
    return const [];
  }

  Future<void> _load() async {
    final saved = await _store.read();
    if (!ref.mounted) return;
    state = [...saved, ...state];
  }

  /// Waiting to send (not refused) for [key].
  OutboxItem? waitingFor(String key) => state.where((i) => i.key == key && i.refusal == null).firstOrNull;

  /// Turned down by the server, for [key].
  OutboxItem? refusedFor(String key) => state.where((i) => i.key == key && i.refusal != null).firstOrNull;

  /// Keeps work a web form could not send for want of a connection
  /// (docs/offline-web.md, O3). False off the web or with nobody signed in -
  /// the form then shows its error as before.
  Future<bool> keepFromWeb({
    required OutboxKind kind,
    required String key,
    required String label,
    required Map<String, dynamic> payload,
  }) async {
    final me = _me;
    if (!ref.read(offlineWorkProvider) || me == null) return false;

    await add(OutboxItem(kind: kind, key: key, userId: me, label: label, payload: payload, savedAt: DateTime.now()));
    return true;
  }

  /// Keeps [item] - replacing anything older about the same thing - and
  /// starts sending.
  Future<void> add(OutboxItem item) async {
    await _loaded;
    if (!ref.mounted) return;

    state = [
      for (final other in state)
        if (other.key != item.key) other,
      item,
    ];
    await _store.save(state);
    unawaited(flush());
  }

  /// The person has read a refusal.
  Future<void> dismiss(String key) async {
    state = [
      for (final item in state)
        if (!(item.key == key && item.refusal != null)) item,
    ];
    await _store.save(state);
  }

  Future<void> retryNow() async {
    _retryTimer?.cancel();
    _failures = 0;
    await flush();
  }

  Future<void> flush() async {
    await _loaded;
    final me = _me;
    if (!ref.mounted || _sending || me == null) return;

    final mine = [
      for (final item in state)
        if (item.userId == me && item.refusal == null) item,
    ];
    if (mine.isEmpty) return;

    _retryTimer?.cancel();
    _sending = true;
    try {
      for (final item in mine) {
        await _send(item);
      }
      _failures = 0;
    } on Failure catch (failure) {
      if (failure.code != 'NETWORK_ERROR') debugPrint('Sending saved work failed: ${failure.code}');
      _scheduleRetry();
    } catch (error) {
      debugPrint('Sending saved work failed unexpectedly: $error');
      _scheduleRetry();
    } finally {
      _sending = false;
    }
  }

  Future<void> _send(OutboxItem item) async {
    try {
      switch (item.kind) {
        case OutboxKind.report:
          await _sendReport(item);
        case OutboxKind.marks:
          await _sendMarks(item);
        case OutboxKind.staffRegister:
          await _sendStaffRegister(item);
        case OutboxKind.leave:
          await _sendLeave(item);
        case OutboxKind.notice:
          await _sendNotice(item);
        case OutboxKind.feePayment:
          // Made into the receipt, or kept on the server to settle: either
          // way it is there now, and nothing is left to send.
          await ref.read(offlineFeesRepositoryProvider).send(item.payload);
      }
      await _settle(item);
    } on Failure catch (failure) {
      if (_tryAgainLater(failure)) rethrow;
      // Already there - sent once before the answer was lost, or filed from
      // another phone. Either way nothing is left to send.
      if (failure.code == 'TEACHING_REPORT_ALREADY_SUBMITTED') {
        await _settle(item);
        return;
      }
      await _settle(item, refusedBecause: failure.message);
    }
  }

  /// No connection, the server failing, or asked to slow down: nothing is
  /// wrong with the work itself, so it waits and is tried again - never
  /// turned into a refusal (a fee payment taken offline must not stall on a
  /// server hiccup).
  static bool _tryAgainLater(Failure failure) {
    if (const {'NETWORK_ERROR', 'SERVER_ERROR', 'TOO_MANY_REQUESTS'}.contains(failure.code)) return true;
    final status = failure.details['status'];
    return status is int && (status >= 500 || status == 429);
  }

  Future<void> _sendReport(OutboxItem item) async {
    final p = item.payload;
    await ref
        .read(teachingReportRepositoryProvider)
        .store(
          timetableEntryId: p['timetable_entry_id'] as int,
          reportDate: p['report_date'] as String,
          topicTaught: p['topic_taught'] as String,
          syllabusTopicId: p['syllabus_topic_id'] as int?,
          homework: p['homework'] as String?,
          remarks: p['remarks'] as String?,
        );
    if (!ref.mounted) return;
    ref.invalidate(todayProvider);
    ref.invalidate(myReportsProvider);
  }

  Future<void> _sendMarks(OutboxItem item) async {
    final p = item.payload;
    final entries = [
      for (final row in (p['marks'] as List).cast<Map<String, dynamic>>())
        SheetEntry(
          studentId: row['student_id'] as int,
          studentName: '',
          admissionNumber: '',
          rollNumber: null,
          marksObtained: row['marks_obtained'] as String?,
          isAbsent: row['is_absent'] as bool? ?? false,
          grade: null,
          percentage: null,
          passed: null,
          remarks: row['remarks'] as String?,
        ),
    ];
    await ref.read(assessmentRepositoryProvider).saveMarks(p['assessment_id'] as int, entries);
    if (ref.mounted) ref.invalidate(myTestsProvider);
  }

  // The web office's work saved with no connection (docs/offline-web.md, O3).

  Future<void> _sendStaffRegister(OutboxItem item) async {
    final p = item.payload;
    await ref
        .read(staffAttendanceRepositoryProvider)
        .submit(
          schoolId: p['school_id'] as int?,
          departmentId: p['department_id'] as int?,
          attendanceDate: p['attendance_date'] as String,
          records: (p['records'] as List).cast<Map<String, dynamic>>(),
          confirmLeave: p['confirm_leave'] as bool? ?? false,
        );
  }

  Future<void> _sendLeave(OutboxItem item) async {
    final p = item.payload;
    await ref
        .read(staffLeaveRepositoryProvider)
        .apply(
          leaveType: LeaveType.fromApiValue(p['leave_type'] as String),
          startDate: p['start_date'] as String,
          endDate: p['end_date'] as String,
          reason: p['reason'] as String,
        );
  }

  Future<void> _sendNotice(OutboxItem item) async {
    final p = item.payload;
    await ref
        .read(announcementRepositoryProvider)
        .publish(
          schoolId: p['school_id'] as int?,
          title: p['title'] as String,
          body: p['body'] as String,
          audienceType: AnnouncementAudience.fromApiValue(p['audience_type'] as String),
          audienceId: p['audience_id'] as int?,
          channels: p['channels'] as String,
          expiresAt: p['expires_at'] as String?,
          replyQuestion: p['reply_question'] as String?,
          replyBy: p['reply_by'] as String?,
          attachmentIds: [for (final id in (p['attachment_ids'] as List? ?? const [])) id as int],
        );
  }

  Future<void> _settle(OutboxItem item, {String? refusedBecause}) async {
    if (!ref.mounted) return;

    state = [
      for (final other in state)
        if (other.key != item.key) other else if (refusedBecause != null) item.refused(refusedBecause),
    ];
    await _store.save(state);

    // A refused report goes back into its draft: the period's form opens on
    // the words, with the reason above them.
    if (refusedBecause != null && item.kind == OutboxKind.report) {
      final p = item.payload;
      await ref
          .read(reportNotesProvider)
          .saveDraft(
            p['timetable_entry_id'] as int,
            p['report_date'] as String,
            ReportWords(
              topic: p['topic_taught'] as String,
              homework: p['homework'] as String? ?? '',
              remarks: p['remarks'] as String? ?? '',
            ),
          );
    }
  }

  void _scheduleRetry() {
    if (!ref.mounted) return;

    _failures++;
    final delay = retryDelays[min(_failures, retryDelays.length) - 1];
    _retryTimer?.cancel();
    _retryTimer = Timer(delay, flush);
  }
}

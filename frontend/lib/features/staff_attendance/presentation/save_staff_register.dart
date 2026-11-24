import 'package:flutter/material.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/widgets/confirm_dialog.dart';
import '../application/staff_attendance_register_notifier.dart';

/// Submits or updates the register. Marking present somebody on leave that
/// day - approved or applied for - is asked about first (decided
/// 2026-11-02): the server names them, and the office may know better.
///
/// Shared by the website's Staff Attendance and the HOD's Department tab in
/// the Staff app (docs/mobile-apps-review.md, 7.1), so both ask the same.
/// Returns true once the register is saved.
Future<bool> saveStaffRegister(
  BuildContext context,
  StaffAttendanceRegisterNotifier notifier, {
  required bool submitted,
}) async {
  var confirmLeave = false;

  while (true) {
    try {
      await notifier.submitOrUpdate(confirmLeave: confirmLeave);
      if (context.mounted) {
        final l10n = context.l10n;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(submitted ? l10n.staffAttendanceUpdated : l10n.staffAttendanceSubmitted)),
        );
      }
      return true;
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (!context.mounted) return false;

      if (failure.code == 'STAFF_ON_LEAVE' && !confirmLeave) {
        confirmLeave = await confirmDialog(
          context,
          title: context.l10n.staffOnLeaveThatDay,
          message: failure.message,
          confirmLabel: context.l10n.staffMarkPresentAnyway,
        );
        if (confirmLeave) continue;
        return false;
      }

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.localizedMessage(context))));
      return false;
    }
  }
}

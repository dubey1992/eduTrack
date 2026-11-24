import '../../../core/l10n/l10n.dart';
import '../../assessments/data/models/assessment.dart';
import '../../communication/data/models/message.dart';
import '../../staff_attendance/data/models/staff_attendance_status.dart';
import '../../staff_leave/data/models/leave_status.dart';
import '../../staff_leave/data/models/leave_type.dart';
import '../../timetable/data/models/day_of_week.dart';

/// The Staff app's words for labels the web office also shows
/// (docs/mobile-apps-review.md, M11). The models keep their English
/// [LeaveType.label], [LeaveStatus.label] and [DayOfWeek.label] for the
/// office; the phone says them in the person's language.

String leaveTypeLabel(AppLocalizations l10n, LeaveType type) => switch (type) {
  LeaveType.casual => l10n.staffLeaveCasual,
  LeaveType.medical => l10n.staffLeaveMedical,
  LeaveType.earned => l10n.staffLeaveEarned,
  LeaveType.halfDay => l10n.staffLeaveHalfDay,
};

/// A leave type the server named by its API value; an unknown one as sent.
String leaveTypeLabelOf(AppLocalizations l10n, String apiValue) {
  for (final type in LeaveType.values) {
    if (type.apiValue == apiValue) return leaveTypeLabel(l10n, type);
  }

  return apiValue;
}

String leaveStatusLabel(AppLocalizations l10n, LeaveStatus status) => switch (status) {
  LeaveStatus.pending => l10n.staffLeavePending,
  LeaveStatus.approved => l10n.staffLeaveApproved,
  LeaveStatus.rejected => l10n.staffLeaveRejected,
  LeaveStatus.withdrawn => l10n.staffLeaveWithdrawn,
};

String dayLabel(AppLocalizations l10n, DayOfWeek day) => switch (day) {
  DayOfWeek.monday => l10n.staffDayMonday,
  DayOfWeek.tuesday => l10n.staffDayTuesday,
  DayOfWeek.wednesday => l10n.staffDayWednesday,
  DayOfWeek.thursday => l10n.staffDayThursday,
  DayOfWeek.friday => l10n.staffDayFriday,
  DayOfWeek.saturday => l10n.staffDaySaturday,
  DayOfWeek.sunday => l10n.staffDaySunday,
};

String dayShortLabel(AppLocalizations l10n, DayOfWeek day) => switch (day) {
  DayOfWeek.monday => l10n.staffDayMon,
  DayOfWeek.tuesday => l10n.staffDayTue,
  DayOfWeek.wednesday => l10n.staffDayWed,
  DayOfWeek.thursday => l10n.staffDayThu,
  DayOfWeek.friday => l10n.staffDayFri,
  DayOfWeek.saturday => l10n.staffDaySat,
  DayOfWeek.sunday => l10n.staffDaySun,
};

String staffAttendanceLabel(AppLocalizations l10n, StaffAttendanceStatus status) => switch (status) {
  StaffAttendanceStatus.present => l10n.staffPresent,
  StaffAttendanceStatus.absent => l10n.staffAbsent,
  StaffAttendanceStatus.leave => l10n.staffNavLeave,
  StaffAttendanceStatus.halfDay => l10n.staffLeaveHalfDay,
};

String messageCategoryLabel(AppLocalizations l10n, MessageCategory category) => switch (category) {
  MessageCategory.attendance => l10n.staffCategoryAttendance,
  MessageCategory.transport => l10n.staffCategoryTransport,
  MessageCategory.leave => l10n.staffNavLeave,
  MessageCategory.result => l10n.staffCategoryResult,
  MessageCategory.announcement => l10n.staffCategoryAnnouncement,
  MessageCategory.general => l10n.staffCategoryGeneral,
  MessageCategory.emergency => l10n.staffCategoryEmergency,
  MessageCategory.fee => l10n.staffNavFees,
  MessageCategory.teaching => l10n.staffNavTeaching,
};

/// A payment mode by its API value - payroll's and fees' enums share the
/// words but not the type. An unknown one in [fallback], as sent.
String paymentModeLabel(AppLocalizations l10n, String apiValue, String fallback) => switch (apiValue) {
  'cash' => l10n.staffModeCash,
  'bank_transfer' => l10n.staffModeBankTransfer,
  'upi' => l10n.staffModeUpi,
  'cheque' => l10n.staffModeCheque,
  'card' => l10n.staffModeCard,
  'online' || 'online_transfer' => l10n.staffModeOnlineTransfer,
  _ => fallback,
};

String assessmentTypeLabel(AppLocalizations l10n, AssessmentType type) => switch (type) {
  AssessmentType.classTest => l10n.staffTestClassTest,
  AssessmentType.unitTest => l10n.staffTestUnitTest,
  AssessmentType.assignment => l10n.staffTestAssignment,
  AssessmentType.quiz => l10n.staffTestQuiz,
  AssessmentType.practical => l10n.staffTestPractical,
};

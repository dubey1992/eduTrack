import '../../../core/l10n/l10n.dart';
import '../data/models/family_bus.dart';
import '../data/models/family_day.dart';
import '../data/models/family_fees.dart';
import '../data/models/family_guardian_invite.dart';
import '../data/models/family_learning.dart';
import '../data/models/family_records.dart';

/// The Family models' plain words in the parent's language
/// (docs/mobile-apps-review.md, M11).
///
/// The models keep their English getters - the home-screen widget, built
/// without a screen, still reads them - and the screens read these.

extension AttendanceMarkWords on AttendanceMark {
  String words(AppLocalizations l10n) => switch (this) {
    AttendanceMark.present => l10n.familyMarkPresent,
    AttendanceMark.absent => l10n.familyMarkAbsent,
    AttendanceMark.leave => l10n.familyMarkLeave,
    AttendanceMark.notMarked => l10n.familyMarkNotMarked,
  };
}

extension InstalmentStatusWords on InstalmentStatus {
  String words(AppLocalizations l10n) => switch (this) {
    InstalmentStatus.paid => l10n.familyFeeStatusPaid,
    InstalmentStatus.partPaid => l10n.familyFeeStatusPartPaid,
    InstalmentStatus.due => l10n.familyFeeStatusDue,
    InstalmentStatus.overdue => l10n.familyFeeStatusOverdue,
    InstalmentStatus.waived => l10n.familyFeeStatusWaived,
  };
}

extension FamilyReceiptWords on FamilyReceipt {
  String paymentModeWords(AppLocalizations l10n) => switch (paymentMode) {
    'cash' => l10n.familyPayModeCash,
    'upi' => 'UPI',
    'bank_transfer' => l10n.familyPayModeBankTransfer,
    'cheque' => l10n.familyPayModeCheque,
    'card' => l10n.familyPayModeCard,
    'online_transfer' => l10n.familyPayModeOnlineTransfer,
    _ => paymentMode,
  };
}

extension FamilyGuardianInviteWords on FamilyGuardianInvite {
  String statusWords(AppLocalizations l10n) => switch (status) {
    'approved' => l10n.familyInviteApproved,
    'declined' => l10n.familyInviteDeclined,
    _ => l10n.familyInviteWaiting,
  };
}

/// mother, father, guardian or other, in words.
String guardianRelationshipWords(AppLocalizations l10n, String relationship) => switch (relationship) {
  'mother' => l10n.familyRelationMother,
  'father' => l10n.familyRelationFather,
  'guardian' => l10n.familyRelationGuardian,
  _ => l10n.familyRelationOther,
};

extension BusTripWords on BusTrip {
  /// [BusTrip.summary], in the parent's language.
  String summaryWords(AppLocalizations l10n) {
    if (status == 'cancelled') return l10n.familyTripCancelled;

    return switch (riderStatus) {
      'boarded' when !isRunning => isPickup ? l10n.familyTripReachedSchool : l10n.familyTripEnded,
      'boarded' => isPickup ? l10n.familyTripOnBusToSchool : l10n.familyTripOnBusHome,
      'dropped' => isPickup ? l10n.familyTripReachedSchool : l10n.familyTripDroppedAtStop,
      'absent' => l10n.familyTripNotTaken,
      _ => isRunning ? l10n.familyTripOnItsWay : l10n.familyTripEnded,
    };
  }
}

extension BusMarkWords on BusMark {
  /// [BusMark.proof], in the parent's language; the name, role and stop as
  /// the school wrote them.
  String? proofWords(AppLocalizations l10n) {
    if (by == null) return null;
    final who = byRole == null ? by! : '${by!} ($byRole)';
    return stopName == null ? l10n.familyMarkedBy(who) : l10n.familyMarkedByAt(who, stopName!);
  }
}

extension FamilyNoticeWords on FamilyNotice {
  String kindWords(AppLocalizations l10n) => switch (category) {
    'attendance' => l10n.familyKindAttendance,
    'transport' => l10n.familyKindBus,
    'fee' => l10n.familyKindFees,
    'result' => l10n.familyKindResults,
    'emergency' => l10n.familyKindEmergency,
    'announcement' => l10n.familyKindNotice,
    _ => l10n.familyKindMessage,
  };
}

extension TestResultWords on TestResult {
  /// "18 / 20", or "Absent" in the parent's language.
  String scoreWords(AppLocalizations l10n) => isAbsent ? l10n.familyMarkAbsent : score;
}

import '../../../core/l10n/l10n.dart';
import '../../transport/data/models/transport_trip.dart';

/// The Bus app's words for the transport enums, in the person's language
/// (docs/mobile-apps-review.md, M11). The models keep their English
/// `label`, which the web office shows.
extension TripDirectionWords on TripDirection {
  String labelIn(AppLocalizations l10n) => switch (this) {
    TripDirection.pickup => l10n.busPickup,
    TripDirection.drop => l10n.busDrop,
  };

  /// "Start pickup" / "Start drop".
  String startIn(AppLocalizations l10n) => switch (this) {
    TripDirection.pickup => l10n.busStartPickup,
    TripDirection.drop => l10n.busStartDrop,
  };

  /// "Continue pickup" / "Continue drop".
  String continueIn(AppLocalizations l10n) => switch (this) {
    TripDirection.pickup => l10n.busContinuePickup,
    TripDirection.drop => l10n.busContinueDrop,
  };
}

extension TripRiderStatusWords on TripRiderStatus {
  String labelIn(AppLocalizations l10n) => switch (this) {
    TripRiderStatus.pending => l10n.busStatusPending,
    TripRiderStatus.boarded => l10n.busStatusBoarded,
    TripRiderStatus.dropped => l10n.busStatusDropped,
    TripRiderStatus.absent => l10n.busStatusAbsent,
  };

  /// "Aarav boarded" - said after one tap.
  String markedIn(AppLocalizations l10n, String name) => switch (this) {
    TripRiderStatus.pending => l10n.busMarkedPending(name),
    TripRiderStatus.boarded => l10n.busMarkedBoarded(name),
    TripRiderStatus.dropped => l10n.busMarkedDropped(name),
    TripRiderStatus.absent => l10n.busMarkedAbsent(name),
  };
}

extension TripStatusWords on TripStatus {
  /// The badge on a trip: "En route", "Completed", "Cancelled".
  String badgeIn(AppLocalizations l10n) => switch (this) {
    TripStatus.inProgress => l10n.busEnRoute,
    TripStatus.completed => l10n.busCompleted,
    TripStatus.cancelled => l10n.busCancelled,
  };
}

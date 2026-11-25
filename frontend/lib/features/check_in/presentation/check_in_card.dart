import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/l10n/failure_text.dart';
import '../../../core/l10n/l10n.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/status_badge.dart';
import '../../my_trip/data/location_source.dart';
import '../../staff_attendance/data/models/staff_attendance_status.dart';
import '../../today/presentation/staff_words.dart';
import '../application/check_in_notifier.dart';
import '../data/models/my_attendance_day.dart';

/// Checking in and out, at the top of the day (docs/staff-check-in.md).
///
/// The first thing on Today, and deliberately not a gate: a teacher who
/// forgets still takes the register, and the card keeps asking. One button
/// whose job changes through the day - Check in, then Check out - and the
/// times the register now holds.
///
/// The edge cases it speaks to (docs/staff-check-in.md, "Edge cases"): a
/// check-out asks first, so a pocket tap cannot end somebody's day; location
/// off or refused for good comes with the button that opens the setting; no
/// signal says nothing was recorded; half-day leave, a day the office
/// changed, and a day somebody forgot to check out of are each said once.
class CheckInCard extends ConsumerStatefulWidget {
  const CheckInCard({super.key});

  @override
  ConsumerState<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends ConsumerState<CheckInCard> {
  bool _busy = false;
  Failure? _problem;

  Future<void> _act({required bool arriving}) async {
    if (_busy) return;

    if (!arriving && !await _confirmCheckOut()) return;

    setState(() {
      _busy = true;
      _problem = null;
    });

    try {
      final notifier = ref.read(checkInProvider.notifier);
      final day = arriving ? await notifier.checkIn() : await notifier.checkOut();
      if (!mounted) return;
      final time = arriving ? day.checkIn : day.checkOut;
      final l10n = context.l10n;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            time == null
                ? (arriving ? l10n.staffCheckedIn : l10n.staffCheckedOut)
                : (arriving ? l10n.staffCheckedInAt(formatClock(time)) : l10n.staffCheckedOutAt(formatClock(time))),
          ),
        ),
      );
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _problem = failure);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// A check-out ends somebody's day on the register; one stray tap should
  /// not. The app's own dialog, never the platform's alert.
  Future<bool> _confirmCheckOut() async {
    final day = ref.read(checkInProvider).value;
    final l10n = context.l10n;
    final since = day?.checkIn == null ? '' : ' ${l10n.staffYouCheckedInAt(formatClock(day!.checkIn!))}';
    final again = day?.checkOut != null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('check-out-confirm'),
        title: Text(again ? l10n.staffCheckOutAgainQ : l10n.staffCheckOutNowQ),
        content: Text(again ? l10n.staffCheckOutAgainBody : '${l10n.staffCheckOutBody}$since'),
        actions: [
          TextButton(
            key: const Key('check-out-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(l10n.staffNotYet),
          ),
          FilledButton(
            key: const Key('check-out-confirm-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(l10n.staffCheckOut),
          ),
        ],
      ),
    );

    return confirmed ?? false;
  }

  Future<void> _openSettings(LocationAccess access) async {
    final location = ref.read(locationSourceProvider);
    final opened = access == LocationAccess.serviceOff
        ? await location.openLocationSettings()
        : await location.openAppSettings();
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(context.l10n.staffOpenSettingsForLocation)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(checkInProvider);

    return day.when(
      // A line's height while it loads, so Today does not jump when it lands.
      loading: () => const SizedBox(height: 4, child: LinearProgressIndicator()),
      error: (error, _) {
        // An account with no employment record behind it has no day on the
        // staff register to check in to; retrying will not change that.
        if (error is Failure && error.code == 'NO_STAFF_RECORD') return const _NoStaffRecord();

        return _LoadFailed(onRetry: () => ref.read(checkInProvider.notifier).retry());
      },
      data: (day) {
        if (day.hidden) return const SizedBox.shrink();

        return _Card(
          day: day,
          busy: _busy,
          problem: _problem,
          onCheckIn: () => _act(arriving: true),
          onCheckOut: () => _act(arriving: false),
          onOpenSettings: _openSettings,
        );
      },
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({
    required this.day,
    required this.busy,
    required this.problem,
    required this.onCheckIn,
    required this.onCheckOut,
    required this.onOpenSettings,
  });

  final MyAttendanceDay day;
  final bool busy;
  final Failure? problem;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;
  final ValueChanged<LocationAccess> onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.appColors;
    final waiting = day.canCheckIn;
    final l10n = context.l10n;

    final (title, detail) = _words(l10n, day);
    final notes = _notes(l10n, day);

    return Card(
      key: const Key('check-in-card'),
      color: waiting ? scheme.primaryContainer : null,
      shape: waiting
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: BorderSide(color: scheme.primary.withValues(alpha: 0.4)),
            )
          : null,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  day.checkIn == null ? Icons.fingerprint : Icons.how_to_reg_outlined,
                  color: scheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, key: const Key('check-in-title'), style: theme.textTheme.titleMedium),
                      const SizedBox(height: 2),
                      Text(detail, style: TextStyle(color: colors.muted, height: 1.35)),
                      if (day.late || day.status != null) ...[
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: [
                            if (day.status != null)
                              StatusBadge(
                                label: staffAttendanceLabel(l10n, day.status!),
                                tone: day.status == StaffAttendanceStatus.present
                                    ? BadgeTone.success
                                    : day.status == StaffAttendanceStatus.absent
                                    ? BadgeTone.danger
                                    : BadgeTone.info,
                              ),
                            if (day.late)
                              StatusBadge(
                                key: const Key('check-in-late'),
                                label: l10n.staffLate,
                                tone: BadgeTone.warning,
                              ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            for (final note in notes) ...[const SizedBox(height: 10), note],
            if (problem != null) ...[
              const SizedBox(height: 12),
              _Problem(failure: problem!, onOpenSettings: onOpenSettings),
            ],
            if (day.canCheckIn || day.canCheckOut) ...[
              const SizedBox(height: 14),
              ConstrainedBox(
                // A minimum, not a fixed height: the label grows with large text (M11, 3.4).
                constraints: const BoxConstraints(minHeight: 48, minWidth: double.infinity),
                child: day.canCheckIn
                    ? FilledButton.icon(
                        key: const Key('check-in-button'),
                        onPressed: busy ? null : onCheckIn,
                        icon: _icon(busy, Icons.login, scheme.onPrimary),
                        label: Text(busy ? l10n.staffFindingLocation : l10n.staffCheckIn),
                      )
                    : OutlinedButton.icon(
                        key: const Key('check-out-button'),
                        onPressed: busy ? null : onCheckOut,
                        icon: _icon(busy, Icons.logout, scheme.primary),
                        label: Text(
                          busy
                              ? l10n.staffFindingLocation
                              : day.checkOut == null
                              ? l10n.staffCheckOut
                              : l10n.staffCheckOutAgain,
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(l10n.staffLocationUsedOnce(day.radiusMetres), style: TextStyle(fontSize: 12, color: colors.muted)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _icon(bool busy, IconData icon, Color color) => busy
      ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: color))
      : Icon(icon);

  /// What the card says, by where the day has got to.
  (String, String) _words(AppLocalizations l10n, MyAttendanceDay day) {
    if (day.blockedReason != null) return (l10n.staffCheckInUnavailable, day.blockedReason!);

    final checkIn = day.checkIn;
    final checkOut = day.checkOut;

    if (checkIn == null) {
      if (day.markedBySomeoneElse && day.status == StaffAttendanceStatus.absent) {
        return (l10n.staffMarkedAbsent, l10n.staffMarkedAbsentBody);
      }
      if (day.halfDayLeave) {
        return (l10n.staffHalfDayLeaveToday, l10n.staffHalfDayLeaveBody);
      }
      return (l10n.staffCheckInToStart, l10n.staffCheckInToStartBody);
    }

    if (checkOut == null) return (l10n.staffCheckedInAtTitle(formatClock(checkIn)), l10n.staffCheckOutWhenLeaving);

    final hours = day.workingHours == null ? '' : ' · ${day.workingHours}';
    return ('${formatClock(checkIn)} – ${formatClock(checkOut)}$hours', l10n.staffCheckedInAndOut);
  }

  /// The lines that are true only some days.
  List<Widget> _notes(AppLocalizations l10n, MyAttendanceDay day) {
    return [
      if (day.unfinishedDay != null)
        _Note(
          key: const Key('check-in-unfinished'),
          icon: Icons.history,
          text: l10n.staffUnfinishedDay(
            DateFormat('EEE, MMM d').format(day.unfinishedDay!.date),
            formatClock(day.unfinishedDay!.checkIn),
          ),
        ),
      if (day.markedBySomeoneElse && day.checkIn != null)
        _Note(key: const Key('check-in-office-changed'), icon: Icons.edit_note, text: l10n.staffOfficeUpdatedDay),
    ];
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: colors.warning),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(fontSize: 13, height: 1.35))),
      ],
    );
  }
}

/// Why the last tap did not count, and - where there is one - the thing to
/// press to put it right.
class _Problem extends StatelessWidget {
  const _Problem({required this.failure, required this.onOpenSettings});

  final Failure failure;
  final ValueChanged<LocationAccess> onOpenSettings;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;
    final l10n = context.l10n;

    // No signal: the time on the register is the moment the tap reaches
    // the school, so a tap that never arrived recorded nothing - and saying
    // so stops somebody believing they are checked in.
    final message = switch (failure.code) {
      'NETWORK_ERROR' => l10n.staffCheckInNoConnection,
      // The phone's own location troubles (check_in_notifier.locationFailure).
      'LOCATION_SERVICEOFF' => l10n.staffLocationServiceOff,
      'LOCATION_DENIEDFOREVER' => l10n.staffLocationDeniedForever,
      'LOCATION_DENIED' => l10n.staffLocationDenied,
      'LOCATION_UNSUPPORTED' => l10n.staffLocationUnsupported,
      'LOCATION_GRANTED' => l10n.staffLocationNotFound,
      _ => failure.localizedMessage(context),
    };

    final fix = switch (failure.code) {
      'LOCATION_SERVICEOFF' => (l10n.staffTurnOnLocation, LocationAccess.serviceOff),
      'LOCATION_DENIEDFOREVER' => (l10n.staffOpenSettings, LocationAccess.deniedForever),
      _ => null,
    };

    return Container(
      key: const Key('check-in-problem'),
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: TextStyle(color: colors.onDangerContainer, height: 1.35)),
          if (fix != null)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('check-in-open-settings'),
                onPressed: () => onOpenSettings(fix.$2),
                icon: const Icon(Icons.settings_outlined, size: 18),
                label: Text(fix.$1),
              ),
            ),
        ],
      ),
    );
  }
}

class _LoadFailed extends StatelessWidget {
  const _LoadFailed({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('check-in-load-failed'),
      child: ListTile(
        leading: const Icon(Icons.cloud_off_outlined),
        title: Text(context.l10n.staffCheckInLoadFailed),
        trailing: TextButton(onPressed: onRetry, child: Text(context.l10n.retry)),
      ),
    );
  }
}

class _NoStaffRecord extends StatelessWidget {
  const _NoStaffRecord();

  @override
  Widget build(BuildContext context) {
    return Card(
      key: const Key('check-in-no-staff-record'),
      child: ListTile(
        leading: const Icon(Icons.badge_outlined),
        title: Text(context.l10n.staffNoStaffRecord),
        subtitle: Text(context.l10n.staffNoStaffRecordBody),
      ),
    );
  }
}

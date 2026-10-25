import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/status_badge.dart';
import '../../my_trip/data/location_source.dart';
import '../../staff_attendance/data/models/staff_attendance_status.dart';
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            time == null
                ? (arriving ? 'Checked in.' : 'Checked out.')
                : '${arriving ? 'Checked in' : 'Checked out'} at ${formatClock(time)}.',
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
    final since = day?.checkIn == null ? '' : ' You checked in at ${formatClock(day!.checkIn!)}.';
    final again = day?.checkOut != null;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        key: const Key('check-out-confirm'),
        title: Text(again ? 'Check out again?' : 'Check out now?'),
        content: Text(
          again
              ? 'Your leaving time will change to now. The last check-out is the one that counts.'
              : 'This records the time you leave school.$since',
        ),
        actions: [
          TextButton(
            key: const Key('check-out-cancel'),
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Not yet'),
          ),
          FilledButton(
            key: const Key('check-out-confirm-button'),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Check out'),
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
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text("Open your phone's settings and allow location for School365ai.")));
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

    final (title, detail) = _words(day);
    final notes = _notes(day);

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
                                label: day.status!.label,
                                tone: day.status == StaffAttendanceStatus.present
                                    ? BadgeTone.success
                                    : day.status == StaffAttendanceStatus.absent
                                    ? BadgeTone.danger
                                    : BadgeTone.info,
                              ),
                            if (day.late)
                              const StatusBadge(key: Key('check-in-late'), label: 'Late', tone: BadgeTone.warning),
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
              SizedBox(
                width: double.infinity,
                height: 48,
                child: day.canCheckIn
                    ? FilledButton.icon(
                        key: const Key('check-in-button'),
                        onPressed: busy ? null : onCheckIn,
                        icon: _icon(busy, Icons.login, scheme.onPrimary),
                        label: Text(busy ? 'Finding your location…' : 'Check in'),
                      )
                    : OutlinedButton.icon(
                        key: const Key('check-out-button'),
                        onPressed: busy ? null : onCheckOut,
                        icon: _icon(busy, Icons.logout, scheme.primary),
                        label: Text(
                          busy
                              ? 'Finding your location…'
                              : day.checkOut == null
                              ? 'Check out'
                              : 'Check out again',
                        ),
                      ),
              ),
              const SizedBox(height: 8),
              Text(
                'Your location is used once, to confirm you are within ${day.radiusMetres} m of school. '
                'It is not stored.',
                style: TextStyle(fontSize: 12, color: colors.muted),
              ),
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
  (String, String) _words(MyAttendanceDay day) {
    if (day.blockedReason != null) return ('Check-in unavailable', day.blockedReason!);

    final checkIn = day.checkIn;
    final checkOut = day.checkOut;

    if (checkIn == null) {
      if (day.markedBySomeoneElse && day.status == StaffAttendanceStatus.absent) {
        return ('Marked absent today', 'The office marked you absent. Check in when you arrive and it is corrected.');
      }
      if (day.halfDayLeave) {
        return ('Half-day leave today', 'Check in for the half you work, and the day is recorded as a half day.');
      }
      return ('Check in to start your day', 'Tap Check in when you reach school.');
    }

    if (checkOut == null) return ('Checked in at ${formatClock(checkIn)}', 'Check out when you leave school.');

    final hours = day.workingHours == null ? '' : ' · ${day.workingHours}';
    return ('${formatClock(checkIn)} – ${formatClock(checkOut)}$hours', 'Checked in and out. See you tomorrow.');
  }

  /// The lines that are true only some days.
  List<Widget> _notes(MyAttendanceDay day) {
    return [
      if (day.unfinishedDay != null)
        _Note(
          key: const Key('check-in-unfinished'),
          icon: Icons.history,
          text:
              'You did not check out on ${DateFormat('EEE, MMM d').format(day.unfinishedDay!.date)} '
              '(checked in ${formatClock(day.unfinishedDay!.checkIn)}). Ask the office to add when you left.',
        ),
      if (day.markedBySomeoneElse && day.checkIn != null)
        const _Note(
          key: Key('check-in-office-changed'),
          icon: Icons.edit_note,
          text: 'The office has updated your day on the register. Ask them if something looks wrong.',
        ),
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

    // No signal: the time on the register is the moment the tap reaches
    // the school, so a tap that never arrived recorded nothing - and saying
    // so stops somebody believing they are checked in.
    final message = failure.code == 'NETWORK_ERROR'
        ? 'No connection, so nothing was recorded. Check in again when your phone is online - '
              'the time saved is when it reaches the school.'
        : failure.message;

    final fix = switch (failure.code) {
      'LOCATION_SERVICEOFF' => ('Turn on location', LocationAccess.serviceOff),
      'LOCATION_DENIEDFOREVER' => ('Open settings', LocationAccess.deniedForever),
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
        title: const Text('Could not load your check-in'),
        trailing: TextButton(onPressed: onRetry, child: const Text('Retry')),
      ),
    );
  }
}

class _NoStaffRecord extends StatelessWidget {
  const _NoStaffRecord();

  @override
  Widget build(BuildContext context) {
    return const Card(
      key: Key('check-in-no-staff-record'),
      child: ListTile(
        leading: Icon(Icons.badge_outlined),
        title: Text('Check-in is not set up for your account'),
        subtitle: Text('Your account has no staff record at this school. Ask the office to add one.'),
      ),
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/status_badge.dart';
import '../../staff_attendance/data/models/staff_attendance_status.dart';
import '../application/check_in_notifier.dart';
import '../data/models/my_attendance_day.dart';

/// Checking in and out, at the top of the day (docs/staff-check-in.md).
///
/// The first thing on Today, and deliberately not a gate: a teacher who
/// forgets still takes the register, and the card keeps asking. One button
/// whose job changes through the day - Check in, then Check out - and the
/// times the register now holds.
class CheckInCard extends ConsumerStatefulWidget {
  const CheckInCard({super.key});

  @override
  ConsumerState<CheckInCard> createState() => _CheckInCardState();
}

class _CheckInCardState extends ConsumerState<CheckInCard> {
  bool _busy = false;
  String? _problem;

  Future<void> _act({required bool arriving}) async {
    if (_busy) return;
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
      if (mounted) setState(() => _problem = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final day = ref.watch(checkInProvider);

    return day.when(
      // A line's height while it loads, so Today does not jump when it lands.
      loading: () => const SizedBox(height: 4, child: LinearProgressIndicator()),
      error: (error, _) => _LoadFailed(onRetry: () => ref.read(checkInProvider.notifier).retry()),
      data: (day) {
        if (day.hidden) return const SizedBox.shrink();

        return _Card(
          day: day,
          busy: _busy,
          problem: _problem,
          onCheckIn: () => _act(arriving: true),
          onCheckOut: () => _act(arriving: false),
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
  });

  final MyAttendanceDay day;
  final bool busy;
  final String? problem;
  final VoidCallback onCheckIn;
  final VoidCallback onCheckOut;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final colors = context.appColors;
    final waiting = day.canCheckIn;

    final (title, detail) = _words(day);

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
            if (problem != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('check-in-problem'),
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: colors.dangerContainer, borderRadius: BorderRadius.circular(8)),
                child: Text(problem!, style: TextStyle(color: colors.onDangerContainer, height: 1.35)),
              ),
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
      return ('Check in to start your day', 'Tap Check in when you reach school.');
    }

    if (checkOut == null) return ('Checked in at ${formatClock(checkIn)}', 'Check out when you leave school.');

    final hours = day.workingHours == null ? '' : ' · ${day.workingHours}';
    return ('${formatClock(checkIn)} – ${formatClock(checkOut)}$hours', 'Checked in and out. See you tomorrow.');
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

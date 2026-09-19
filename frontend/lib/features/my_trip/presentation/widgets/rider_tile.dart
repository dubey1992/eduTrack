import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/status_badge.dart';
import '../../../transport/data/models/transport_trip.dart';
import '../../data/apply_marks.dart';

/// One child on the trip: who, how they stand, and big buttons for what can
/// happen next - Boarded / Dropped / Absent, each enabled only when the
/// child's state allows it - plus Call Parent. The guardian's number is never
/// shown: the button hands it straight to the dialler.
class RiderTile extends StatelessWidget {
  const RiderTile({
    super.key,
    required this.rider,
    required this.running,
    required this.onMark,
    required this.onCallParent,
  });

  final TripRider rider;

  /// The trip is still in progress; a finished trip shows the outcome only.
  final bool running;
  final void Function(TripRiderStatus status) onMark;
  final VoidCallback onCallParent;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final hasNumber = (rider.guardianMobile ?? '').trim().isNotEmpty;

    return Container(
      key: Key('rider-${rider.studentId}'),
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(rider.name, style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    Text(
                      [if (rider.classSectionName != null) rider.classSectionName!, rider.admissionNumber].join(' · '),
                      style: TextStyle(color: muted),
                    ),
                  ],
                ),
              ),
              StatusBadge(label: rider.status.label, tone: _toneFor(rider.status)),
              if (running) ...[
                const SizedBox(width: 8),
                if (hasNumber)
                  IconButton.filledTonal(
                    key: Key('call-parent-${rider.studentId}'),
                    tooltip: 'Call parent',
                    iconSize: 26,
                    onPressed: onCallParent,
                    icon: const Icon(Icons.call),
                  )
                else
                  Tooltip(
                    message: 'No number on record',
                    child: IconButton.filledTonal(
                      key: Key('call-parent-${rider.studentId}'),
                      iconSize: 26,
                      onPressed: null,
                      icon: const Icon(Icons.call),
                    ),
                  ),
              ],
            ],
          ),
          if (running) ...[
            const SizedBox(height: 10),
            Row(
              children: [
                for (final (status, icon) in const [
                  (TripRiderStatus.boarded, Icons.login),
                  (TripRiderStatus.dropped, Icons.logout),
                  (TripRiderStatus.absent, Icons.person_off_outlined),
                ]) ...[
                  Expanded(
                    child: _MarkButton(
                      key: Key('mark-${status.apiValue}-${rider.studentId}'),
                      label: status.label,
                      icon: icon,
                      onPressed: riderCanBecome(rider.status, status) ? () => onMark(status) : null,
                    ),
                  ),
                  if (status != TripRiderStatus.absent) const SizedBox(width: 8),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }

  BadgeTone _toneFor(TripRiderStatus status) => switch (status) {
    TripRiderStatus.pending => BadgeTone.neutral,
    TripRiderStatus.boarded => BadgeTone.info,
    TripRiderStatus.dropped => BadgeTone.success,
    TripRiderStatus.absent => BadgeTone.warning,
  };
}

class _MarkButton extends StatelessWidget {
  const _MarkButton({super.key, required this.label, required this.icon, required this.onPressed});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: FilledButton.tonal(
        onPressed: onPressed,
        style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 4)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 20),
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/not_sent_mark.dart';

/// The marks the server turned down, each with its reason and what to do
/// about it: try again while the trip runs, or tell the office.
class NotSentCard extends StatelessWidget {
  const NotSentCard({super.key, required this.marks, required this.onDismiss, this.onRetry});

  final List<NotSentMark> marks;
  final ValueChanged<NotSentMark> onDismiss;

  /// Null once the trip is over: nothing more can be recorded on it.
  final ValueChanged<NotSentMark>? onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = context.appColors;

    return Card(
      key: const Key('not-sent-card'),
      margin: const EdgeInsets.only(bottom: 16),
      color: colors.dangerContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(
                'Not sent',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 16, color: colors.onDangerContainer),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
              child: Text(
                onRetry == null
                    ? 'The school did not record these. Tell your school office, who can correct the trip.'
                    : 'The school did not record these. Try again if something has changed, '
                          'or tell your school office, who can correct the trip.',
                key: const Key('not-sent-help'),
                style: TextStyle(color: colors.onDangerContainer, fontSize: 13),
              ),
            ),
            for (final mark in marks)
              ListTile(
                leading: Icon(Icons.error_outline, color: colors.onDangerContainer),
                title: Text(
                  mark.label,
                  style: TextStyle(color: colors.onDangerContainer, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(mark.reason, style: TextStyle(color: colors.onDangerContainer)),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onRetry != null && mark.mark != null)
                      IconButton(
                        key: Key('not-sent-retry-${mark.clientId}'),
                        tooltip: 'Try again',
                        icon: Icon(Icons.refresh, color: colors.onDangerContainer),
                        onPressed: () => onRetry!(mark),
                      ),
                    IconButton(
                      tooltip: 'Dismiss',
                      icon: Icon(Icons.close, color: colors.onDangerContainer),
                      onPressed: () => onDismiss(mark),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

import 'package:flutter/material.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/models/not_sent_mark.dart';

/// The marks the server turned down, each with its reason, for the attendant
/// to read and dismiss.
class NotSentCard extends StatelessWidget {
  const NotSentCard({super.key, required this.marks, required this.onDismiss});

  final List<NotSentMark> marks;
  final ValueChanged<NotSentMark> onDismiss;

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
            for (final mark in marks)
              ListTile(
                leading: Icon(Icons.error_outline, color: colors.onDangerContainer),
                title: Text(
                  mark.label,
                  style: TextStyle(color: colors.onDangerContainer, fontWeight: FontWeight.w700),
                ),
                subtitle: Text(mark.reason, style: TextStyle(color: colors.onDangerContainer)),
                trailing: IconButton(
                  tooltip: 'Dismiss',
                  icon: Icon(Icons.close, color: colors.onDangerContainer),
                  onPressed: () => onDismiss(mark),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

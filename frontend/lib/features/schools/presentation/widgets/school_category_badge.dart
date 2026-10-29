import 'package:flutter/material.dart';

import '../../../../core/widgets/status_badge.dart';
import '../../data/models/school.dart';

/// A school's category as a pill (docs/school-categories.md), with how long
/// a trial has left beneath it. An ended trial reads in red: the school
/// still works, but somebody should decide what it is now.
class SchoolCategoryBadge extends StatelessWidget {
  const SchoolCategoryBadge({super.key, required this.school});

  final School school;

  BadgeTone get _tone => switch (school.category) {
    SchoolCategory.live => BadgeTone.info,
    SchoolCategory.trial => (school.trialDaysLeft ?? 0) < 0 ? BadgeTone.danger : BadgeTone.warning,
    SchoolCategory.demo || SchoolCategory.testing => BadgeTone.neutral,
  };

  @override
  Widget build(BuildContext context) {
    final note = school.trialNote;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        StatusBadge(label: school.category.label, tone: _tone),
        if (note != null) ...[
          const SizedBox(height: 2),
          Text(note, style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
        ],
      ],
    );
  }
}

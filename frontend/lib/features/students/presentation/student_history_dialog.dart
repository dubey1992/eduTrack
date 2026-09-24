import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../application/student_enrollment_notifier.dart';
import '../data/models/student.dart';
import '../data/models/student_enrollment.dart';

/// Which class a student was in, year by year (docs/promotion.md).
///
/// Read-only, and open to every role that may see the student: a teacher
/// asking what a child did last year should not need an administrator.
class StudentHistoryDialog extends ConsumerWidget {
  const StudentHistoryDialog({super.key, required this.student});

  final Student student;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final historyState = ref.watch(studentEnrollmentsProvider(student.id));

    return AlertDialog(
      title: Text('History · ${student.name}'),
      content: ConstrainedBox(
        // Bounded so the spinner does not stretch the dialog to the full
        // viewport height before the history arrives.
        constraints: const BoxConstraints(minWidth: 460, maxWidth: 460, maxHeight: 420),
        child: AsyncValueView<List<StudentEnrollment>>(
          value: historyState,
          onRetry: () => ref.read(studentEnrollmentsProvider(student.id).notifier).refresh(),
          isEmpty: (rows) => rows.isEmpty,
          emptyBuilder: (context) => const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'No years recorded yet. A year appears once the student is placed in a class '
              'while that year is the current one.',
            ),
          ),
          data: (context, rows) {
            return SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [for (final row in rows) _YearRow(enrollment: row)],
              ),
            );
          },
        ),
      ),
      actions: [FilledButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Done'))],
    );
  }
}

class _YearRow extends StatelessWidget {
  const _YearRow({required this.enrollment});

  final StudentEnrollment enrollment;

  @override
  Widget build(BuildContext context) {
    final roll = enrollment.rollNumber;

    return ListTile(
      dense: true,
      title: Text(enrollment.classLabel),
      subtitle: Text(
        roll == null ? enrollment.academicYearName : '${enrollment.academicYearName} · Roll $roll',
        style: TextStyle(color: context.appColors.muted),
      ),
      trailing: StatusBadge(label: enrollment.status.label, tone: _toneFor(enrollment.status)),
    );
  }

  static BadgeTone _toneFor(EnrollmentStatus status) {
    return switch (status) {
      EnrollmentStatus.studying => BadgeTone.info,
      EnrollmentStatus.promoted || EnrollmentStatus.graduated => BadgeTone.success,
      EnrollmentStatus.retained => BadgeTone.warning,
      EnrollmentStatus.left => BadgeTone.neutral,
    };
  }
}

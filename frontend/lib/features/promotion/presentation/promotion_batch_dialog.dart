import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';
import '../data/models/promotion_batch.dart';
import '../data/promotion_repository.dart';

/// One promotion, student by student (docs/promotion.md).
///
/// Read on demand rather than carried in the history list: forty rows per
/// batch is a lot to send for a list nobody has opened yet.
final promotionBatchProvider = FutureProvider.autoDispose.family<PromotionBatch, int>((ref, batchId) {
  return ref.watch(promotionRepositoryProvider).batch(batchId);
});

class PromotionBatchDialog extends ConsumerWidget {
  const PromotionBatchDialog({super.key, required this.batchId});

  final int batchId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final batch = ref.watch(promotionBatchProvider(batchId));

    return AlertDialog(
      title: Text(batch.value == null ? 'Promotion' : _title(batch.value!)),
      content: SizedBox(
        width: 760,
        child: AsyncValueView<PromotionBatch>(
          value: batch,
          onRetry: () => ref.invalidate(promotionBatchProvider(batchId)),
          isEmpty: (value) => value.students.isEmpty,
          emptyBuilder: (context) =>
              const Padding(padding: EdgeInsets.symmetric(vertical: 24), child: Text('This run recorded no students.')),
          data: (context, value) => SingleChildScrollView(child: _Table(batch: value)),
        ),
      ),
      actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))],
    );
  }

  String _title(PromotionBatch batch) {
    final when = batch.runAt == null ? '' : ' · ${formatDate(batch.runAt!)}';

    return '${batch.fromClassSectionName} → ${batch.toAcademicYearName}$when';
  }
}

class _Table extends StatelessWidget {
  const _Table({required this.batch});

  final PromotionBatch batch;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Run by ${batch.runByName}. '
          '${batch.promotedCount} promoted, ${batch.retainedCount} retained, '
          '${batch.graduatedCount} graduated, ${batch.leftCount} left out.',
          style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        HorizontalScrollTable(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Student')),
              DataColumn(label: Text('Admission')),
              DataColumn(label: Text('From')),
              DataColumn(label: Text('Outcome')),
              DataColumn(label: Text('To')),
            ],
            rows: [
              for (final student in batch.students)
                DataRow(
                  cells: [
                    DataCell(Text(student.name)),
                    DataCell(Text(student.admissionNumber)),
                    DataCell(Text('${student.fromClassName} ${student.fromSectionName ?? ''}'.trim())),
                    DataCell(Text(student.outcomeLabel)),
                    DataCell(Text(student.destination)),
                  ],
                ),
            ],
          ),
        ),
      ],
    );
  }
}

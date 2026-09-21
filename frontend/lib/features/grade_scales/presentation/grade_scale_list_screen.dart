import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/module_access.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/grade_scale_notifier.dart';
import '../data/models/grade_scale.dart';
import 'grade_scale_dialog.dart';

/// The grade scales a school keeps, and their bands (docs/assessments.md).
///
/// Readable by every role - a teacher entering marks needs to know what an 81
/// will be called - and editable by an administrator.
class GradeScaleListScreen extends ConsumerStatefulWidget {
  const GradeScaleListScreen({super.key});

  @override
  ConsumerState<GradeScaleListScreen> createState() => _GradeScaleListScreenState();
}

class _GradeScaleListScreenState extends ConsumerState<GradeScaleListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final scalesState = ref.watch(gradeScaleListNotifierProvider);
    final canManage = ref.watch(authNotifierProvider).value?.canManage(AppModules.academics) ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Grade Scales',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const GradeScaleDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Grade Scale'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(gradeScaleListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<GradeScale>>(
            value: scalesState,
            onRetry: () => ref.read(gradeScaleListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No grade scales yet. A scale turns a percentage into a grade, '
                  'so add one before results are published.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _ScaleList(scales: page.items, canManage: canManage),
                      desktop: (context) => _ScaleList(scales: page.items, canManage: canManage, wide: true),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(gradeScaleListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(gradeScaleListNotifierProvider.notifier).setPerPage(p),
                  ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

/// One card per scale, with its bands as chips.
///
/// A table was the other option and reads worse here: a scale's bands are a
/// list of their own, and a row per band would repeat the scale's name down
/// the page.
class _ScaleList extends StatelessWidget {
  const _ScaleList({required this.scales, required this.canManage, this.wide = false});

  final List<GradeScale> scales;
  final bool canManage;
  final bool wide;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: EdgeInsets.all(wide ? 20 : 16),
      itemCount: scales.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) => _ScaleCard(scale: scales[index], canManage: canManage),
    );
  }
}

class _ScaleCard extends ConsumerWidget {
  const _ScaleCard({required this.scale, required this.canManage});

  final GradeScale scale;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Flexible(child: Text(scale.name, style: Theme.of(context).textTheme.titleMedium)),
                      const SizedBox(width: 8),
                      if (scale.isDefault) const StatusBadge(label: 'Default', tone: BadgeTone.success),
                      if (scale.schoolName != null) ...[
                        const SizedBox(width: 8),
                        Flexible(child: Text(scale.schoolName!, overflow: TextOverflow.ellipsis)),
                      ],
                    ],
                  ),
                ),
                if (canManage) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 20),
                    tooltip: 'Edit scale',
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => GradeScaleDialog(scale: scale),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 20),
                    tooltip: 'Delete scale',
                    onPressed: () => _confirmDelete(context, ref),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final band in scale.bands)
                  Chip(
                    label: Text('${band.label}  ${band.range}'),
                    avatar: band.isFailing ? const Icon(Icons.remove_circle_outline, size: 16) : null,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete grade scale?'),
        content: Text('This will permanently delete "${scale.name}" and its bands. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(gradeScaleListNotifierProvider.notifier).deleteScale(scale);
      messenger.showSnackBar(SnackBar(content: Text('${scale.name} was deleted.')));
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

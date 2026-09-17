import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/models/user_role.dart';
import '../../../core/network/paged_list.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/pagination_controls.dart';
import '../../../core/widgets/responsive.dart';
import '../../../core/widgets/school_filter_dropdown.dart';
import '../../../core/widgets/section_header.dart';
import '../../../core/widgets/status_badge.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/academic_year_list_notifier.dart';
import '../data/models/academic_year.dart';
import 'add_academic_year_dialog.dart';
import 'edit_academic_year_dialog.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/horizontal_scroll_table.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin};

class AcademicYearListScreen extends ConsumerStatefulWidget {
  const AcademicYearListScreen({super.key});

  @override
  ConsumerState<AcademicYearListScreen> createState() => _AcademicYearListScreenState();
}

class _AcademicYearListScreenState extends ConsumerState<AcademicYearListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final yearsState = ref.watch(academicYearListNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Academic Years',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddAcademicYearDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Academic Year'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(academicYearListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<AcademicYear>>(
            value: yearsState,
            onRetry: () => ref.read(academicYearListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No academic years set up yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _AcademicYearListMobile(years: page.items, canManage: canManage),
                      desktop: (context) => _AcademicYearListDesktop(years: page.items, canManage: canManage),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(academicYearListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(academicYearListNotifierProvider.notifier).setPerPage(p),
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

class _AcademicYearListMobile extends StatelessWidget {
  const _AcademicYearListMobile({required this.years, required this.canManage});

  final List<AcademicYear> years;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: years.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final year = years[index];
        return Card(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: ListTile(
              title: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(child: Text(year.name, overflow: TextOverflow.ellipsis)),
                  const SizedBox(width: 8),
                  if (year.isCurrent) const StatusBadge(label: 'Current', tone: BadgeTone.success),
                ],
              ),
              subtitle: Text(
                '${formatDate(year.startDate)} - ${formatDate(year.endDate)}'
                '${year.schoolName != null ? '\n${year.schoolName}' : ''}',
              ),
              isThreeLine: year.schoolName != null,
              trailing: canManage ? _AcademicYearActions(year: year) : null,
            ),
          ),
        );
      },
    );
  }
}

class _AcademicYearListDesktop extends StatelessWidget {
  const _AcademicYearListDesktop({required this.years, required this.canManage});

  final List<AcademicYear> years;
  final bool canManage;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Card(
        child: HorizontalScrollTable(
          child: DataTable(
            columns: const [
              DataColumn(label: Text('Name')),
              DataColumn(label: Text('School')),
              DataColumn(label: Text('Start')),
              DataColumn(label: Text('End')),
              DataColumn(label: Text('Status')),
              DataColumn(label: Text('Action')),
            ],
            rows: [
              for (final year in years)
                DataRow(
                  cells: [
                    DataCell(Text(year.name)),
                    DataCell(Text(year.schoolName ?? '-')),
                    DataCell(Text(formatDate(year.startDate))),
                    DataCell(Text(formatDate(year.endDate))),
                    DataCell(
                      year.isCurrent
                          ? const StatusBadge(label: 'Current', tone: BadgeTone.success)
                          : const StatusBadge(label: 'Past/Upcoming', tone: BadgeTone.neutral),
                    ),
                    DataCell(canManage ? _AcademicYearActions(year: year) : const SizedBox.shrink()),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AcademicYearActions extends ConsumerWidget {
  const _AcademicYearActions({required this.year});

  final AcademicYear year;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (!year.isCurrent)
          TextButton(
            onPressed: () async {
              try {
                await ref.read(academicYearListNotifierProvider.notifier).setCurrent(year);
                if (context.mounted) {
                  ScaffoldMessenger.of(context)
                      .showSnackBar(SnackBar(content: Text('${year.name} is now the current academic year.')));
                }
              } catch (error) {
                if (context.mounted) _showErrorSnackBar(context, error);
              }
            },
            child: const Text('Set Current'),
          ),
        IconButton(
          icon: const Icon(Icons.edit_outlined, size: 20),
          tooltip: 'Edit',
          onPressed: () => showDialog(
            context: context,
            builder: (_) => EditAcademicYearDialog(academicYear: year),
          ),
        ),
        IconButton(
          icon: const Icon(Icons.delete_outline, size: 20),
          tooltip: 'Delete',
          onPressed: () => _confirmDelete(context, ref),
        ),
      ],
    );
  }

  Future<void> _confirmDelete(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete academic year?'),
        content: Text('This will permanently delete "${year.name}". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(academicYearListNotifierProvider.notifier).deleteAcademicYear(year);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${year.name} was deleted.')));
      }
    } catch (error) {
      if (context.mounted) _showErrorSnackBar(context, error);
    }
  }
}

void _showErrorSnackBar(BuildContext context, Object error) {
  final failure = error is Failure ? error : Failure.unknown(error.toString());
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(failure.message)));
}

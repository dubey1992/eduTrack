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
import '../../auth/application/auth_notifier.dart';
import '../application/school_class_list_notifier.dart';
import '../data/models/school_class.dart';
import 'add_class_dialog.dart';
import 'add_section_dialog.dart';
import 'edit_class_dialog.dart';
import 'edit_section_dialog.dart';

const _manageRoles = {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin};

class ClassListScreen extends ConsumerStatefulWidget {
  const ClassListScreen({super.key});

  @override
  ConsumerState<ClassListScreen> createState() => _ClassListScreenState();
}

class _ClassListScreenState extends ConsumerState<ClassListScreen> {
  int? _schoolFilter;

  @override
  Widget build(BuildContext context) {
    final classesState = ref.watch(schoolClassListNotifierProvider);
    final canManage = _manageRoles.contains(ref.watch(authNotifierProvider).value?.role);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Classes & Sections',
          actions: [
            if (canManage)
              FilledButton.icon(
                onPressed: () => showDialog(context: context, builder: (_) => const AddClassDialog()),
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Add Class'),
              ),
            SchoolFilterDropdown(
              selected: _schoolFilter,
              onChanged: (schoolId) {
                setState(() => _schoolFilter = schoolId);
                ref.read(schoolClassListNotifierProvider.notifier).setSchoolFilter(schoolId);
              },
            ),
          ],
        ),
        Expanded(
          child: AsyncValueView<PagedList<SchoolClass>>(
            value: classesState,
            onRetry: () => ref.read(schoolClassListNotifierProvider.notifier).refresh(),
            isEmpty: (page) => page.items.isEmpty,
            emptyBuilder: (context) => const Center(child: Text('No classes set up yet.')),
            data: (context, page) {
              return Column(
                children: [
                  Expanded(
                    child: ResponsiveBuilder(
                      mobile: (context) => _ClassGrid(classes: page.items, canManage: canManage, crossAxisCount: 1),
                      desktop: (context) => _ClassGrid(classes: page.items, canManage: canManage, crossAxisCount: 3),
                    ),
                  ),
                  PaginationControls(
                    currentPage: page.currentPage,
                    lastPage: page.lastPage,
                    total: page.total,
                    perPage: page.perPage,
                    onPageChanged: (p) => ref.read(schoolClassListNotifierProvider.notifier).goToPage(p),
                    onPerPageChanged: (p) => ref.read(schoolClassListNotifierProvider.notifier).setPerPage(p),
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

class _ClassGrid extends StatelessWidget {
  const _ClassGrid({required this.classes, required this.canManage, required this.crossAxisCount});

  final List<SchoolClass> classes;
  final bool canManage;
  final int crossAxisCount;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        mainAxisExtent: 260,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
      ),
      itemCount: classes.length,
      itemBuilder: (context, index) => _ClassCard(schoolClass: classes[index], canManage: canManage),
    );
  }
}

class _ClassCard extends ConsumerWidget {
  const _ClassCard({required this.schoolClass, required this.canManage});

  final SchoolClass schoolClass;
  final bool canManage;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: Text(schoolClass.name, style: Theme.of(context).textTheme.titleMedium)),
                if (canManage) ...[
                  IconButton(
                    icon: const Icon(Icons.edit_outlined, size: 18),
                    tooltip: 'Edit class',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => showDialog(
                      context: context,
                      builder: (_) => EditClassDialog(schoolClass: schoolClass),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Delete class',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _confirmDeleteClass(context, ref),
                  ),
                ],
              ],
            ),
            if (schoolClass.academicYearName != null)
              Text(
                schoolClass.academicYearName!,
                style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            const SizedBox(height: 8),
            Expanded(
              child: schoolClass.sections.isEmpty
                  ? const Center(child: Text('No sections yet.'))
                  : ListView.builder(
                      itemCount: schoolClass.sections.length,
                      itemBuilder: (context, index) {
                        final section = schoolClass.sections[index];
                        return ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('Section ${section.name}'),
                          subtitle: Text(
                            [
                              if (section.roomNumber != null) section.roomNumber!,
                              if (section.classTeacherName != null) 'Teacher: ${section.classTeacherName}',
                            ].join(' · '),
                          ),
                          trailing: canManage
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: const Icon(Icons.edit_outlined, size: 16),
                                      tooltip: 'Edit section',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => showDialog(
                                        context: context,
                                        builder: (_) =>
                                            EditSectionDialog(schoolId: schoolClass.schoolId, section: section),
                                      ),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.close, size: 16),
                                      tooltip: 'Delete section',
                                      visualDensity: VisualDensity.compact,
                                      onPressed: () => _confirmDeleteSection(context, ref, section),
                                    ),
                                  ],
                                )
                              : null,
                        );
                      },
                    ),
            ),
            if (canManage)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton.icon(
                  onPressed: () => showDialog(
                    context: context,
                    builder: (_) => AddSectionDialog(schoolClass: schoolClass),
                  ),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Section'),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteClass(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete class?'),
        content: Text('This will permanently delete "${schoolClass.name}". This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(schoolClassListNotifierProvider.notifier).deleteClass(schoolClass);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${schoolClass.name} was deleted.')));
      }
    } catch (error) {
      if (context.mounted) _showErrorSnackBar(context, error);
    }
  }

  Future<void> _confirmDeleteSection(BuildContext context, WidgetRef ref, ClassSection section) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete section?'),
        content: Text('This will permanently delete Section ${section.name}. This cannot be undone.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.of(context).pop(true), child: const Text('Delete')),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ref.read(schoolClassListNotifierProvider.notifier).deleteSection(section);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Section ${section.name} was deleted.')));
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

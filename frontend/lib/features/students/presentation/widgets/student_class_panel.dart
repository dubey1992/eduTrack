import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/async_value_view.dart';
import '../../application/student_list_notifier.dart';
import '../../data/models/student_class_group.dart';

/// Which part of the roll the Students page shows: everybody, or one section
/// (docs/onboarding.md).
class StudentSectionChoice {
  const StudentSectionChoice({required this.id, required this.label, required this.students});

  final int id;
  final String label;
  final int students;
}

/// The current year's classes down the side of the Students page, in class
/// order - Nursery, LKG, UKG, Class 1 ... - each section with its count.
class StudentClassPanel extends ConsumerWidget {
  const StudentClassPanel({super.key, required this.schoolId, required this.selected, required this.onSelected});

  final int? schoolId;
  final int? selected;
  final ValueChanged<StudentSectionChoice?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    // The section on show, marked so it reads at a glance.
    final highlight = theme.colorScheme.primaryContainer;

    return Card(
      margin: const EdgeInsets.fromLTRB(20, 0, 0, 20),
      child: AsyncValueView<List<StudentClassGroup>>(
        value: ref.watch(studentClassesProvider(schoolId)),
        onRetry: () => ref.invalidate(studentClassesProvider(schoolId)),
        data: (context, classes) {
          final manySchools = classes.map((c) => c.schoolId).toSet().length > 1;

          return ListView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            children: [
              ListTile(
                dense: true,
                selected: selected == null,
                selectedTileColor: highlight,
                leading: const Icon(Icons.groups_outlined, size: 20),
                title: const Text('All students'),
                onTap: () => onSelected(null),
              ),
              if (classes.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text('No classes in the current year yet.', style: theme.textTheme.bodySmall),
                ),
              for (final group in classes) ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 2),
                  child: Text(
                    manySchools ? '${group.name} · ${group.schoolName}' : group.name,
                    style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
                for (final section in group.sections)
                  ListTile(
                    dense: true,
                    selected: selected == section.id,
                    selectedTileColor: highlight,
                    contentPadding: const EdgeInsets.only(left: 28, right: 16),
                    title: Text('Section ${section.name}'),
                    trailing: Text('${section.students}', style: theme.textTheme.bodySmall),
                    onTap: () => onSelected(
                      StudentSectionChoice(id: section.id, label: group.labelFor(section), students: section.students),
                    ),
                  ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// The same choice on a phone: one dropdown above the list.
class StudentClassPicker extends ConsumerWidget {
  const StudentClassPicker({super.key, required this.schoolId, required this.selected, required this.onSelected});

  final int? schoolId;
  final int? selected;
  final ValueChanged<StudentSectionChoice?> onSelected;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AsyncValueView<List<StudentClassGroup>>(
      value: ref.watch(studentClassesProvider(schoolId)),
      onRetry: () => ref.invalidate(studentClassesProvider(schoolId)),
      data: (context, classes) {
        final choices = [
          for (final group in classes)
            for (final section in group.sections)
              StudentSectionChoice(id: section.id, label: group.labelFor(section), students: section.students),
        ];

        return DropdownButtonFormField<int?>(
          key: ValueKey(selected),
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'Class', isDense: true),
          items: [
            const DropdownMenuItem<int?>(value: null, child: Text('All students')),
            for (final choice in choices)
              DropdownMenuItem<int?>(value: choice.id, child: Text('${choice.label} (${choice.students})')),
          ],
          onChanged: (id) => onSelected(id == null ? null : choices.firstWhere((choice) => choice.id == id)),
        );
      },
    );
  }
}

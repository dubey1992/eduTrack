import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../application/school_list_notifier.dart';
import '../../data/models/school.dart';

/// Which group, if any, a school belongs to.
///
/// Only schools that could actually be a parent are offered: a branch cannot
/// have branches of its own, and a school cannot be its own parent. The API
/// enforces both - this just avoids offering a choice that will be refused.
/// See docs/branches.md.
class ParentSchoolField extends ConsumerWidget {
  const ParentSchoolField({super.key, required this.value, required this.onChanged, this.editing});

  final int? value;
  final ValueChanged<int?> onChanged;

  /// The school being edited, so it cannot be offered as its own parent.
  final School? editing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schools = ref.watch(schoolListNotifierProvider).value ?? const <School>[];

    final candidates = schools.where((school) => !school.isBranch).where((school) => school.id != editing?.id).toList();

    // A school that already has branches cannot become one, so there is
    // nothing to choose.
    if (editing?.isGroupParent ?? false) {
      return const SizedBox.shrink();
    }

    return DropdownButtonFormField<int?>(
      initialValue: candidates.any((s) => s.id == value) ? value : null,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Part of a school group (optional)',
        helperText: 'Leave empty for a standalone school.',
        isDense: true,
      ),
      items: [
        const DropdownMenuItem(value: null, child: Text('Standalone school')),
        for (final school in candidates)
          DropdownMenuItem(
            value: school.id,
            child: Text('Branch of ${school.name}', overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
      ],
      onChanged: onChanged,
    );
  }
}

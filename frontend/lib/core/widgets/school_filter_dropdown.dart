import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/schools/application/school_list_notifier.dart';
import '../../features/schools/data/models/school.dart';
import '../models/user_role.dart';

/// "Filter by school" dropdown for list screens that span every school -
/// only a SUPER_ADMIN ever sees mixed-school data (every other role is
/// already scoped to their own school server-side, so the filter would be
/// meaningless for them and this renders nothing).
class SchoolFilterDropdown extends ConsumerWidget {
  const SchoolFilterDropdown({super.key, required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final role = ref.watch(authNotifierProvider).value?.role;
    if (role != UserRole.superAdmin) return const SizedBox.shrink();

    final schools = ref.watch(schoolListNotifierProvider).value ?? const <School>[];
    final activeSchools = schools.where((s) => s.status == SchoolStatus.active);

    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<int?>(
        initialValue: selected,
        isExpanded: true,
        decoration: const InputDecoration(labelText: 'Filter by school', isDense: true),
        items: [
          const DropdownMenuItem(value: null, child: Text('All Schools', overflow: TextOverflow.ellipsis, maxLines: 1)),
          for (final school in activeSchools)
            DropdownMenuItem(
              value: school.id,
              child: Text(school.name, overflow: TextOverflow.ellipsis, maxLines: 1),
            ),
        ],
        onChanged: onChanged,
      ),
    );
  }
}

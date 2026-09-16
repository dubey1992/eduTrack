import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/schools/application/school_list_notifier.dart';
import '../../features/schools/data/models/school.dart';
import '../models/user_role.dart';

/// "Filter by school" dropdown for list screens that span more than one -
/// a SUPER_ADMIN across the platform, and an admin across the branches of
/// their group. Anybody scoped to a single school server-side would find the
/// filter meaningless, so for them this renders nothing.
class SchoolFilterDropdown extends ConsumerWidget {
  const SchoolFilterDropdown({super.key, required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actor = ref.watch(authNotifierProvider).value;
    // Asked of the user rather than the role: a School Admin sees this in a
    // group and does not in a standalone school, which the role cannot say.
    if (actor == null || !actor.picksSchool) return const SizedBox.shrink();

    final schools = ref.watch(schoolListNotifierProvider).value ?? const <School>[];
    final activeSchools = schools.where((s) => s.status == SchoolStatus.active);

    // A Super Admin is choosing between schools; anybody else between the
    // branches of one group. The list itself is scoped server-side either
    // way - this only changes what it is called.
    final isGroup = actor.role != UserRole.superAdmin;

    return SizedBox(
      width: 220,
      child: DropdownButtonFormField<int?>(
        initialValue: selected,
        isExpanded: true,
        decoration: InputDecoration(labelText: isGroup ? 'Filter by branch' : 'Filter by school', isDense: true),
        items: [
          DropdownMenuItem(
            value: null,
            child: Text(isGroup ? 'Whole group' : 'All Schools', overflow: TextOverflow.ellipsis, maxLines: 1),
          ),
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

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/widgets/async_value_view.dart';
import '../../../schools/application/school_list_notifier.dart';
import '../../../schools/data/models/school.dart';

/// The required "School" dropdown a SUPER_ADMIN gets on every transport
/// form (a SCHOOL_ADMIN is scoped server-side and never sees it).
class TransportSchoolPicker extends ConsumerWidget {
  const TransportSchoolPicker({super.key, required this.selected, required this.onChanged});

  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final schoolsState = ref.watch(schoolListNotifierProvider);

    return AsyncValueView<List<School>>(
      value: schoolsState,
      data: (context, schools) {
        final activeSchools = schools.where((s) => s.status == SchoolStatus.active);
        return DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: const InputDecoration(labelText: 'School'),
          items: [
            for (final school in activeSchools)
              DropdownMenuItem(
                value: school.id,
                child: Text(school.name, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
          ],
          onChanged: onChanged,
          validator: (v) => v == null ? 'School is required' : null,
        );
      },
    );
  }
}

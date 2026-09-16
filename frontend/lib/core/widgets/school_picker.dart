import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/auth/application/auth_notifier.dart';
import '../../features/schools/application/school_list_notifier.dart';
import '../../features/schools/data/models/school.dart';
import '../models/user_role.dart';
import 'async_value_view.dart';

/// "Which school does this record belong to?", for the forms and filters that
/// have to ask.
///
/// Only shown to somebody for whom the answer is genuinely ambiguous - see
/// [AuthenticatedUser.picksSchool]. Everybody else has exactly one school and
/// the server fills it in, so the field would be a dropdown with one option.
///
/// Worded for whoever is looking: a Super Admin is choosing between schools, an
/// admin in a group between the branches of theirs. It is the same list either
/// way - scoped server-side - and the same record; "Branch" simply says what a
/// grouped admin is actually picking, the way the filter above it does.
class SchoolPicker extends ConsumerWidget {
  const SchoolPicker({super.key, required this.selected, required this.onChanged, this.required = true});

  final int? selected;
  final ValueChanged<int?> onChanged;

  /// Whether leaving it unanswered is an error. True on a form, where the
  /// record has to land somewhere; false on a filter, where answering nothing
  /// means "all of them".
  final bool required;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isGroup = ref.watch(authNotifierProvider).value?.role != UserRole.superAdmin;
    final label = isGroup ? 'Branch' : 'School';

    return AsyncValueView<List<School>>(
      value: ref.watch(schoolListNotifierProvider),
      data: (context, schools) {
        final activeSchools = schools.where((s) => s.status == SchoolStatus.active);

        return DropdownButtonFormField<int>(
          initialValue: selected,
          isExpanded: true,
          decoration: InputDecoration(labelText: label),
          items: [
            for (final school in activeSchools)
              DropdownMenuItem(
                value: school.id,
                child: Text(school.name, overflow: TextOverflow.ellipsis, maxLines: 1),
              ),
          ],
          onChanged: onChanged,
          validator: required ? (v) => v == null ? '$label is required' : null : null,
        );
      },
    );
  }
}

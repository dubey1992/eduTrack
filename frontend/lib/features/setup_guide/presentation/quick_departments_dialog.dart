import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../departments/application/department_list_notifier.dart';
import '../application/setup_guide_notifier.dart';
import '../data/models/setup_guide.dart';
import '../data/setup_guide_repository.dart';

final departmentPresetsProvider = FutureProvider.autoDispose<List<DepartmentPreset>>(
  (ref) => ref.watch(setupGuideRepositoryProvider).departmentPresets(),
);

/// The common departments, ticked and added in one step (docs/onboarding.md,
/// O4). Ones the school already has are left alone.
class QuickDepartmentsDialog extends ConsumerStatefulWidget {
  const QuickDepartmentsDialog({super.key});

  @override
  ConsumerState<QuickDepartmentsDialog> createState() => _QuickDepartmentsDialogState();
}

class _QuickDepartmentsDialogState extends ConsumerState<QuickDepartmentsDialog> {
  /// Null until the presets arrive, then what is ticked.
  Set<String>? _ticked;
  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submit(List<DepartmentPreset> presets) async {
    final ticked = _ticked ?? {};
    if (_isSubmitting) return;
    if (ticked.isEmpty) {
      setState(() => _errorMessage = 'Tick at least one department.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await ref.read(setupGuideRepositoryProvider).addDepartments([
        for (final preset in presets)
          if (ticked.contains(preset.name)) preset.name,
      ]);
      ref.invalidate(departmentListNotifierProvider);
      await ref.read(setupGuideNotifierProvider.notifier).refresh();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_summary(result))));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  static String _summary(QuickDepartmentsResult result) {
    final made = result.created.length;
    final created = made == 0
        ? 'No new departments - the school already has them.'
        : 'Added $made ${made == 1 ? 'department' : 'departments'}.';
    if (result.skipped.isEmpty || made == 0) return created;
    return '$created Already there: ${result.skipped.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final presetsState = ref.watch(departmentPresetsProvider);
    // What starts ticked, as soon as the presets are here - the button's
    // count reads it in this same build.
    final presets = presetsState.value;
    if (_ticked == null && presets != null) {
      _ticked = {
        for (final preset in presets)
          if (preset.selected) preset.name,
      };
    }
    final count = _ticked?.length ?? 0;

    return AlertDialog(
      title: const Text('Add common departments'),
      content: SizedBox(
        width: 480,
        child: AsyncValueView<List<DepartmentPreset>>(
          value: presetsState,
          onRetry: () => ref.invalidate(departmentPresetsProvider),
          data: (context, presets) {
            final ticked = _ticked!;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final preset in presets)
                      FilterChip(
                        label: Text(preset.name),
                        selected: ticked.contains(preset.name),
                        onSelected: (on) => setState(() {
                          on ? ticked.add(preset.name) : ticked.remove(preset.name);
                        }),
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  'Departments the school already has are left as they are. Rename or add others on the '
                  'Departments page.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting || presetsState.value == null ? null : () => _submit(presetsState.value!),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(count == 0 ? 'Add departments' : 'Add $count ${count == 1 ? 'department' : 'departments'}'),
        ),
      ],
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/school_picker.dart';
import '../../academic_years/application/academic_year_picker_provider.dart';
import '../../academic_years/data/models/academic_year.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/school_class_list_notifier.dart';
import '../data/models/quick_class_setup.dart';

/// Nursery to Class 10 - or whichever standard classes are ticked - and
/// their sections, in one step (docs/onboarding.md). Classes the year
/// already has are left alone.
class QuickClassSetupDialog extends ConsumerStatefulWidget {
  const QuickClassSetupDialog({super.key});

  @override
  ConsumerState<QuickClassSetupDialog> createState() => _QuickClassSetupDialogState();
}

class _QuickClassSetupDialogState extends ConsumerState<QuickClassSetupDialog> {
  final _formKey = GlobalKey<FormState>();

  int? _schoolId;
  int? _academicYearId;
  int _sections = 1;

  /// Null until the options arrive, then what is ticked to start with.
  Set<String>? _ticked;

  bool _isSubmitting = false;
  String? _errorMessage;

  Future<void> _submit(QuickSetupOptions options) async {
    final ticked = _ticked ?? {};
    if (_isSubmitting || !_formKey.currentState!.validate() || _academicYearId == null) return;
    if (ticked.isEmpty) {
      setState(() => _errorMessage = 'Tick at least one class.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final result = await ref
          .read(schoolClassListNotifierProvider.notifier)
          .quickSetup(
            schoolId: _schoolId,
            academicYearId: _academicYearId!,
            // In class order, whatever order they were ticked in.
            classes: [
              for (final option in options.classes)
                if (ticked.contains(option.name)) option.name,
            ],
            sections: _sections,
          );
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

  static String _summary(QuickSetupResult result) {
    final made = result.created.length;
    final sections = result.sections.join(', ');
    final created = made == 0
        ? 'No new classes - the year already has them.'
        : 'Created $made ${made == 1 ? 'class' : 'classes'}, each with section${result.sections.length == 1 ? '' : 's'} $sections.';
    if (result.skipped.isEmpty || made == 0) return created;
    return '$created Already there, left as they were: ${result.skipped.join(', ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;
    final optionsState = ref.watch(quickSetupOptionsProvider);

    return AlertDialog(
      title: const Text('Quick setup: classes & sections'),
      content: SizedBox(
        width: 560,
        child: AsyncValueView<QuickSetupOptions>(
          value: optionsState,
          onRetry: () => ref.invalidate(quickSetupOptionsProvider),
          data: (context, options) {
            final ticked = _ticked ??= {
              for (final option in options.classes)
                if (option.selected) option.name,
            };

            return SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_errorMessage != null) ...[
                      Text(_errorMessage!, style: TextStyle(color: context.appColors.danger)),
                      const SizedBox(height: 12),
                    ],
                    if (picksSchool) ...[
                      SchoolPicker(
                        selected: _schoolId,
                        onChanged: (value) => setState(() {
                          _schoolId = value;
                          _academicYearId = null;
                        }),
                      ),
                      const SizedBox(height: 10),
                    ],
                    _YearPicker(
                      // A new school's years, not the last school's.
                      key: ValueKey(_schoolId),
                      schoolId: _schoolId,
                      selected: _academicYearId,
                      onChanged: (value) => setState(() => _academicYearId = value),
                    ),
                    const SizedBox(height: 10),
                    DropdownButtonFormField<int>(
                      initialValue: _sections,
                      decoration: const InputDecoration(
                        labelText: 'Sections in each class',
                        helperText: 'Named A, B, C ... Add, rename or remove sections later.',
                      ),
                      items: [
                        for (var n = 1; n <= options.sectionsMax; n++)
                          DropdownMenuItem(
                            value: n,
                            child: Text(n == 1 ? '1 (A)' : '$n (A-${String.fromCharCode(64 + n)})'),
                          ),
                      ],
                      onChanged: (value) => setState(() => _sections = value ?? 1),
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Classes (${ticked.length} ticked)',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        TextButton(
                          onPressed: () => setState(() => _ticked = {for (final o in options.classes) o.name}),
                          child: const Text('Tick all'),
                        ),
                        TextButton(onPressed: () => setState(() => _ticked = {}), child: const Text('Clear')),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (final option in options.classes)
                          FilterChip(
                            label: Text(option.name),
                            selected: ticked.contains(option.name),
                            onSelected: (on) => setState(() {
                              on ? ticked.add(option.name) : ticked.remove(option.name);
                            }),
                          ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Classes this year already has are left as they are.',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting || optionsState.value == null ? null : () => _submit(optionsState.value!),
          child: _isSubmitting
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Text(_ticked == null || _ticked!.isEmpty ? 'Create classes' : 'Create ${_ticked!.length} classes'),
        ),
      ],
    );
  }
}

/// The year the classes go into - the current one, to start with.
class _YearPicker extends ConsumerStatefulWidget {
  const _YearPicker({super.key, required this.schoolId, required this.selected, required this.onChanged});

  final int? schoolId;
  final int? selected;
  final ValueChanged<int?> onChanged;

  @override
  ConsumerState<_YearPicker> createState() => _YearPickerState();
}

class _YearPickerState extends ConsumerState<_YearPicker> {
  bool _defaulted = false;

  @override
  Widget build(BuildContext context) {
    return AsyncValueView<List<AcademicYear>>(
      value: ref.watch(academicYearPickerProvider(widget.schoolId)),
      data: (context, years) {
        if (years.isEmpty) {
          return Text(
            'Add an academic year first - classes belong to a year.',
            style: TextStyle(color: context.appColors.danger),
          );
        }

        if (!_defaulted && widget.selected == null) {
          _defaulted = true;
          final current = years.where((year) => year.isCurrent).firstOrNull ?? years.first;
          WidgetsBinding.instance.addPostFrameCallback((_) => widget.onChanged(current.id));
        }

        return DropdownButtonFormField<int>(
          key: ValueKey(widget.selected),
          initialValue: widget.selected,
          decoration: const InputDecoration(labelText: 'Academic year'),
          items: [for (final year in years) DropdownMenuItem(value: year.id, child: Text(year.name))],
          onChanged: widget.onChanged,
          validator: (v) => v == null ? 'Academic year is required' : null,
        );
      },
    );
  }
}

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/school_picker.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/grade_scale_notifier.dart';
import '../data/grade_scale_presets.dart';
import '../data/models/grade_scale.dart';

/// A whole grade scale: its name, and the bands that turn a percentage into
/// a grade. Saved as one, replacing what was there (docs/assessments.md).
///
/// The bands are edited as rows because that is how they are checked: whether
/// there is a gap, or an overlap, is a question about the set rather than
/// about any one of them.
///
/// A scale grades by marks and percentage, by grade points (each band then
/// carries its points) or by grades alone (docs/document-styles.md); a
/// preset fills the form with a common system to start from.
class GradeScaleDialog extends ConsumerStatefulWidget {
  const GradeScaleDialog({super.key, this.scale});

  final GradeScale? scale;

  @override
  ConsumerState<GradeScaleDialog> createState() => _GradeScaleDialogState();
}

class _BandRow {
  _BandRow({
    String label = '',
    String min = '',
    String max = '',
    String points = '',
    String meaning = '',
    this.isFailing = false,
  }) : label = TextEditingController(text: label),
       min = TextEditingController(text: min),
       max = TextEditingController(text: max),
       points = TextEditingController(text: points),
       meaning = TextEditingController(text: meaning);

  factory _BandRow.of(GradeBand band) => _BandRow(
    label: band.label,
    min: band.minPercentage,
    max: band.maxPercentage,
    points: band.gradePoint ?? '',
    meaning: band.description ?? '',
    isFailing: band.isFailing,
  );

  final TextEditingController label;
  final TextEditingController min;
  final TextEditingController max;
  final TextEditingController points;
  final TextEditingController meaning;
  bool isFailing;

  void dispose() {
    label.dispose();
    min.dispose();
    max.dispose();
    points.dispose();
    meaning.dispose();
  }
}

class _GradeScaleDialogState extends ConsumerState<GradeScaleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.scale?.name ?? '');
  late bool _isDefault = widget.scale?.isDefault ?? false;
  late GradeScaleKind _kind = widget.scale?.kind ?? GradeScaleKind.percentage;
  late final _multiplierController = TextEditingController(text: widget.scale?.gpaMultiplier ?? '');
  late final List<_BandRow> _rows = _startingRows();

  int? _schoolId;
  bool _saving = false;
  String? _error;
  Map<String, List<String>> _fieldErrors = const {};

  bool get _isEdit => widget.scale != null;

  List<_BandRow> _startingRows() {
    final existing = widget.scale?.bands ?? const <GradeBand>[];
    if (existing.isEmpty) {
      // A new scale opens on one row rather than an empty table, so there is
      // something to type into.
      return [_BandRow()];
    }

    return [for (final band in existing) _BandRow.of(band)];
  }

  /// Fills the form from a preset, replacing the bands typed so far. The
  /// name is left alone when the school has already given one.
  void _usePreset(GradeScalePreset preset) {
    setState(() {
      _kind = preset.kind;
      _multiplierController.text = preset.gpaMultiplier ?? '';
      for (final row in _rows) {
        row.dispose();
      }
      _rows
        ..clear()
        ..addAll([for (final band in preset.bands) _BandRow.of(band)]);
      if (_nameController.text.trim().isEmpty) _nameController.text = preset.name;
      _fieldErrors = const {};
      _error = null;
    });
  }

  @override
  void dispose() {
    _nameController.dispose();
    _multiplierController.dispose();
    for (final row in _rows) {
      row.dispose();
    }
    super.dispose();
  }

  String? _serverError(String field) => _fieldErrors[field]?.first;

  /// The server keys band errors by position - `bands.2.min_percentage` - so
  /// the row shows its own.
  String? _bandError(int index, String field) => _serverError('bands.$index.$field');

  Future<void> _submit() async {
    if (_saving || !_formKey.currentState!.validate()) return;

    setState(() {
      _saving = true;
      _error = null;
      _fieldErrors = const {};
    });

    final bands = [
      for (final row in _rows)
        GradeBand(
          id: null,
          label: row.label.text.trim(),
          minPercentage: row.min.text.trim(),
          maxPercentage: row.max.text.trim(),
          isFailing: row.isFailing,
          // Points only mean something on a GPA scale; elsewhere they are not sent.
          gradePoint: _kind == GradeScaleKind.gpa && row.points.text.trim().isNotEmpty ? row.points.text.trim() : null,
          description: row.meaning.text.trim().isEmpty ? null : row.meaning.text.trim(),
        ),
    ];
    final multiplier = _kind == GradeScaleKind.gpa && _multiplierController.text.trim().isNotEmpty
        ? _multiplierController.text.trim()
        : null;

    try {
      final notifier = ref.read(gradeScaleListNotifierProvider.notifier);
      final name = _nameController.text.trim();

      if (_isEdit) {
        await notifier.updateScale(
          widget.scale!,
          name: name,
          isDefault: _isDefault,
          bands: bands,
          kind: _kind,
          gpaMultiplier: multiplier,
        );
      } else {
        await notifier.createScale(
          schoolId: _schoolId,
          name: name,
          isDefault: _isDefault,
          bands: bands,
          kind: _kind,
          gpaMultiplier: multiplier,
        );
      }

      if (mounted) {
        final messenger = ScaffoldMessenger.of(context);
        // Taken before the pop: afterwards this context is defunct, and the
        // message would be posted to a messenger nobody is showing.
        Navigator.of(context).pop();
        messenger.showSnackBar(SnackBar(content: Text(_isEdit ? 'Grade scale saved.' : 'Grade scale created.')));
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) {
        setState(() {
          _fieldErrors = failure.validationErrors;
          // Anything keyed to a field is shown on the field; only what is
          // left over needs the banner.
          _error = _fieldErrors.isEmpty ? failure.message : _fieldErrors['bands']?.first;
        });
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final picksSchool = ref.watch(authNotifierProvider).value?.picksSchool ?? false;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Grade Scale' : 'Add Grade Scale'),
      content: SizedBox(
        width: 800,
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_error != null) ...[
                  Text(_error!, style: TextStyle(color: context.appColors.danger)),
                  const SizedBox(height: 12),
                ],
                if (picksSchool && !_isEdit) ...[
                  SchoolPicker(selected: _schoolId, onChanged: (value) => setState(() => _schoolId = value)),
                  const SizedBox(height: 10),
                ],
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(labelText: 'Name (e.g. Secondary)', errorText: _serverError('name')),
                  maxLength: 50,
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Name is required' : null,
                ),
                CheckboxListTile(
                  value: _isDefault,
                  onChanged: (value) => setState(() => _isDefault = value ?? false),
                  title: const Text('Use this scale by default'),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 12,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SegmentedButton<GradeScaleKind>(
                      key: const Key('grade-scale-kind'),
                      segments: [
                        for (final kind in GradeScaleKind.values) ButtonSegment(value: kind, label: Text(kind.label)),
                      ],
                      selected: {_kind},
                      onSelectionChanged: _saving ? null : (picked) => setState(() => _kind = picked.first),
                    ),
                    PopupMenuButton<GradeScalePreset>(
                      key: const Key('grade-scale-presets'),
                      tooltip: 'Start from a common grading system',
                      onSelected: _usePreset,
                      itemBuilder: (context) => [
                        for (final preset in gradeScalePresets) PopupMenuItem(value: preset, child: Text(preset.name)),
                      ],
                      child: const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.auto_awesome_outlined, size: 18),
                            SizedBox(width: 6),
                            Text('Use a preset'),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(_kindHelp, style: TextStyle(color: context.appColors.muted, fontSize: 12)),
                if (_kind == GradeScaleKind.gpa) ...[
                  const SizedBox(height: 8),
                  SizedBox(
                    width: 320,
                    child: TextFormField(
                      key: const Key('grade-scale-multiplier'),
                      controller: _multiplierController,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'Percentage = GPA × (optional)',
                        helperText: 'Printed beside the GPA only when set, e.g. 9.5.',
                        errorText: _serverError('gpa_multiplier'),
                      ),
                      validator: (v) {
                        final text = v?.trim() ?? '';
                        if (text.isEmpty) return null;
                        final parsed = double.tryParse(text);
                        return parsed == null || parsed <= 0 || parsed > 100 ? 'A number above 0, up to 100' : null;
                      },
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Text('Bands', style: Theme.of(context).textTheme.titleSmall),
                const SizedBox(height: 4),
                Text(
                  'A mark falls in the highest band it reaches. The lowest band must start at 0 '
                  'and the highest must end at 100.',
                  style: TextStyle(color: context.appColors.muted, fontSize: 12),
                ),
                const SizedBox(height: 8),
                for (var index = 0; index < _rows.length; index++) _bandRow(index),
                const SizedBox(height: 4),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _saving ? null : () => setState(() => _rows.add(_BandRow())),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text('Add band'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: _saving ? null : () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _saving ? null : _submit,
          child: _saving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : const Text('Save'),
        ),
      ],
    );
  }

  String get _kindHelp => switch (_kind) {
    GradeScaleKind.percentage => 'Report cards show marks, the percentage and the grade.',
    GradeScaleKind.gpa => 'Report cards also show each subject\'s grade points and the overall GPA.',
    GradeScaleKind.grades => 'Report cards show grades only, with what each one means. No marks or percentages.',
  };

  Widget _bandRow(int index) {
    final row = _rows[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 96,
            child: TextFormField(
              controller: row.label,
              decoration: InputDecoration(labelText: 'Grade', errorText: _bandError(index, 'label')),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: TextFormField(
              controller: row.min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'From %', errorText: _bandError(index, 'min_percentage')),
              validator: _percentage,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 104,
            child: TextFormField(
              controller: row.max,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'To %', errorText: _bandError(index, 'max_percentage')),
              validator: _percentage,
            ),
          ),
          if (_kind == GradeScaleKind.gpa) ...[
            const SizedBox(width: 8),
            SizedBox(
              width: 90,
              child: TextFormField(
                key: Key('grade-band-points-$index'),
                controller: row.points,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                decoration: InputDecoration(labelText: 'Points', errorText: _bandError(index, 'grade_point')),
                validator: (v) {
                  final parsed = double.tryParse(v?.trim() ?? '');
                  if (parsed == null) return 'Number';
                  return parsed < 0 || parsed > 99.99 ? '0-99.99' : null;
                },
              ),
            ),
          ],
          const SizedBox(width: 8),
          Expanded(
            child: TextFormField(
              key: Key('grade-band-meaning-$index'),
              controller: row.meaning,
              maxLength: 60,
              decoration: InputDecoration(
                labelText: 'Meaning (optional)',
                counterText: '',
                errorText: _bandError(index, 'description'),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: FilterChip(
              label: const Text('Fail'),
              selected: row.isFailing,
              onSelected: (value) => setState(() => row.isFailing = value),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Remove band',
            // The last row stays: a scale with no bands grades nothing.
            onPressed: _rows.length == 1
                ? null
                : () => setState(() {
                    _rows.removeAt(index).dispose();
                  }),
          ),
        ],
      ),
    );
  }

  static String? _percentage(String? value) {
    final parsed = double.tryParse(value?.trim() ?? '');
    if (parsed == null) return 'Number';

    return (parsed < 0 || parsed > 100) ? '0-100' : null;
  }
}

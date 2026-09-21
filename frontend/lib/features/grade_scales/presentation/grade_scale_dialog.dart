import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/widgets/school_picker.dart';
import '../../auth/application/auth_notifier.dart';
import '../application/grade_scale_notifier.dart';
import '../data/models/grade_scale.dart';

/// A whole grade scale: its name, and the bands that turn a percentage into
/// a grade. Saved as one, replacing what was there (docs/assessments.md).
///
/// The bands are edited as rows because that is how they are checked: whether
/// there is a gap, or an overlap, is a question about the set rather than
/// about any one of them.
class GradeScaleDialog extends ConsumerStatefulWidget {
  const GradeScaleDialog({super.key, this.scale});

  final GradeScale? scale;

  @override
  ConsumerState<GradeScaleDialog> createState() => _GradeScaleDialogState();
}

class _BandRow {
  _BandRow({String label = '', String min = '', String max = '', this.isFailing = false})
    : label = TextEditingController(text: label),
      min = TextEditingController(text: min),
      max = TextEditingController(text: max);

  final TextEditingController label;
  final TextEditingController min;
  final TextEditingController max;
  bool isFailing;

  void dispose() {
    label.dispose();
    min.dispose();
    max.dispose();
  }
}

class _GradeScaleDialogState extends ConsumerState<GradeScaleDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.scale?.name ?? '');
  late bool _isDefault = widget.scale?.isDefault ?? false;
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

    return [
      for (final band in existing)
        _BandRow(label: band.label, min: band.minPercentage, max: band.maxPercentage, isFailing: band.isFailing),
    ];
  }

  @override
  void dispose() {
    _nameController.dispose();
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
        ),
    ];

    try {
      final notifier = ref.read(gradeScaleListNotifierProvider.notifier);
      final name = _nameController.text.trim();

      if (_isEdit) {
        await notifier.updateScale(widget.scale!, name: name, isDefault: _isDefault, bands: bands);
      } else {
        await notifier.createScale(schoolId: _schoolId, name: name, isDefault: _isDefault, bands: bands);
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
        width: 560,
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
                const SizedBox(height: 4),
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

  Widget _bandRow(int index) {
    final row = _rows[index];

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 90,
            child: TextFormField(
              controller: row.label,
              decoration: InputDecoration(labelText: 'Grade', errorText: _bandError(index, 'label')),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextFormField(
              controller: row.min,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'From %', errorText: _bandError(index, 'min_percentage')),
              validator: _percentage,
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 110,
            child: TextFormField(
              controller: row.max,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: 'To %', errorText: _bandError(index, 'max_percentage')),
              validator: _percentage,
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

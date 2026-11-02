import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/errors/failure.dart';
import '../../../../core/theme/app_colors.dart';
import '../../../schools/application/school_week_provider.dart';
import '../../../schools/data/models/working_week.dart';
import '../../application/break_list_notifier.dart';
import '../../application/break_planner.dart';
import '../../application/period_list_notifier.dart';
import '../../data/models/period.dart';
import '../../data/models/school_break.dart';

/// A ready-made break: one tap fills the name and the length.
class BreakPreset {
  const BreakPreset(this.name, this.minutes, {this.lunch = false});

  final String name;
  final int minutes;
  final bool lunch;

  String get label => '$name · $minutes min';
}

const breakPresets = [
  BreakPreset('Short break', 15),
  BreakPreset('Lunch break', 30, lunch: true),
  BreakPreset('Lunch break', 45, lunch: true),
];

/// Adding or changing a break. Made to be quick: a preset fills the name and
/// length, the time is suggested from the bell schedule, and the form says
/// what the chosen time runs into - offering to move the later periods back
/// when the day is packed, rather than leaving somebody to retype them.
class EditBreakDialog extends ConsumerStatefulWidget {
  const EditBreakDialog({super.key, required this.schoolId, this.existing});

  final int? schoolId;
  final SchoolBreak? existing;

  @override
  ConsumerState<EditBreakDialog> createState() => _EditBreakDialogState();
}

class _EditBreakDialogState extends ConsumerState<EditBreakDialog> {
  final _formKey = GlobalKey<FormState>();
  late final _nameController = TextEditingController(text: widget.existing?.name ?? '');
  late String _dayShape = widget.existing?.dayShape ?? WorkingWeek.fullDay;
  late String? _start = widget.existing?.startTime;
  late String? _end = widget.existing?.endTime;

  /// Which preset is chosen, by index; null for none (custom or editing).
  int? _preset;

  /// Move the later periods back to make room. Ticked for you when needed.
  bool _makeRoom = false;
  bool _isSubmitting = false;
  String? _errorMessage;

  bool get _isEdit => widget.existing != null;

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<Slot> _day(List<Period> periods, List<SchoolBreak> breaks) => slotsOf(
    periods.where((period) => period.dayShape == _dayShape).toList(),
    breaks.where((found) => found.dayShape == _dayShape).toList(),
    ignoringBreak: widget.existing?.id,
  );

  void _choose(int index, List<Slot> day) {
    final preset = breakPresets[index];
    final suggested = suggest(day, preset.minutes, lunch: preset.lunch);

    setState(() {
      _preset = index;
      _nameController.text = preset.name;
      if (suggested != null) {
        _start = suggested.start;
        _end = suggested.end;
      }
      _errorMessage = null;
    });
  }

  Future<void> _pick({required bool isStart}) async {
    final current = isStart ? _start : _end;
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? TimeOfDay.now()
          : TimeOfDay(hour: minutesOf(current) ~/ 60, minute: minutesOf(current) % 60),
    );
    if (picked == null) return;

    final value = clockOf(picked.hour * 60 + picked.minute);
    setState(() {
      if (isStart) {
        // Keep the length when the start moves, so a 30-minute lunch stays
        // 30 minutes.
        final length = (_start != null && _end != null) ? minutesOf(_end!) - minutesOf(_start!) : null;
        _start = value;
        if (length != null && length > 0) _end = clockOf(minutesOf(value) + length);
      } else {
        _end = value;
      }
      _preset = null;
    });
  }

  Future<void> _submit() async {
    if (_isSubmitting || !_formKey.currentState!.validate()) return;
    if (_start == null || _end == null) {
      setState(() => _errorMessage = 'Choose when the break starts and ends.');
      return;
    }

    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    try {
      final notifier = ref.read(breakListNotifierProvider(widget.schoolId).notifier);
      final name = _nameController.text.trim();
      if (_isEdit) {
        await notifier.editBreak(widget.existing!, name: name, startTime: _start, endTime: _end, makeRoom: _makeRoom);
      } else {
        await notifier.create(name: name, dayShape: _dayShape, startTime: _start!, endTime: _end!, makeRoom: _makeRoom);
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_isEdit ? '$name saved.' : '$name added.')));
        Navigator.of(context).pop();
      }
    } catch (error) {
      final failure = error is Failure ? error : Failure.unknown(error.toString());
      if (mounted) setState(() => _errorMessage = failure.message);
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final periods = ref.watch(periodListNotifierProvider(widget.schoolId)).value ?? const <Period>[];
    final breaks = ref.watch(breakListNotifierProvider(widget.schoolId)).value ?? const <SchoolBreak>[];
    final hasHalfDays = ref.watch(schoolWeekProvider(widget.schoolId)).hasHalfDay;
    final day = _day(periods, breaks);
    final colors = context.appColors;

    final found = (_start != null && _end != null && minutesOf(_end!) > minutesOf(_start!))
        ? clashes(day, _start!, _end!)
        : null;
    final needsRoom = found != null && found.overlaps != null;
    // Ticked for you the moment room is needed, and untouched otherwise.
    if (needsRoom && !_makeRoom && !_untickedByHand) _makeRoom = true;
    if (!needsRoom) _makeRoom = false;

    return AlertDialog(
      title: Text(_isEdit ? 'Edit Break' : 'Add Break'),
      content: SizedBox(
        width: 440,
        child: SingleChildScrollView(
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_errorMessage != null) ...[
                  Text(_errorMessage!, style: TextStyle(color: colors.danger)),
                  const SizedBox(height: 12),
                ],
                if (!_isEdit && hasHalfDays) ...[
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: WorkingWeek.fullDay, label: Text('Full day')),
                      ButtonSegment(value: WorkingWeek.halfDay, label: Text('Half day')),
                    ],
                    selected: {_dayShape},
                    onSelectionChanged: (chosen) => setState(() {
                      _dayShape = chosen.first;
                      if (_preset != null) _choose(_preset!, _day(periods, breaks));
                    }),
                  ),
                  const SizedBox(height: 12),
                ],
                if (!_isEdit) ...[
                  Text('Quick choice', style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 6),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      for (final (index, preset) in breakPresets.indexed)
                        ChoiceChip(
                          key: Key('break-preset-$index'),
                          label: Text(preset.label),
                          selected: _preset == index,
                          onSelected: (_) => _choose(index, day),
                        ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'The time is suggested from your periods. Change anything you like.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(color: colors.muted),
                  ),
                  const SizedBox(height: 12),
                ],
                TextFormField(
                  key: const Key('break-name'),
                  controller: _nameController,
                  maxLength: 50,
                  decoration: const InputDecoration(labelText: 'Name', hintText: 'e.g. Lunch break', counterText: ''),
                  validator: (v) => (v ?? '').trim().isEmpty ? 'Give the break a name' : null,
                ),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(child: _timeBox('Starts', _start, () => _pick(isStart: true), const Key('break-start'))),
                    const SizedBox(width: 10),
                    Expanded(child: _timeBox('Ends', _end, () => _pick(isStart: false), const Key('break-end'))),
                  ],
                ),
                const SizedBox(height: 10),
                if (found?.startsDuring != null)
                  _Note(
                    key: const Key('break-starts-during'),
                    icon: Icons.error_outline,
                    colour: colors.danger,
                    text:
                        'This starts during ${found!.startsDuring!.label} (${found.startsDuring!.times}). '
                        'Start it at ${clockOf(found.startsDuring!.end)}, when that ends.',
                  )
                else if (needsRoom)
                  CheckboxListTile(
                    key: const Key('break-make-room'),
                    contentPadding: EdgeInsets.zero,
                    controlAffinity: ListTileControlAffinity.leading,
                    value: _makeRoom,
                    onChanged: (value) => setState(() {
                      _makeRoom = value ?? false;
                      _untickedByHand = !_makeRoom;
                    }),
                    title: Text('Move later periods back by ${found.roomNeeded} min'),
                    subtitle: Text(
                      'It overlaps ${found.overlaps!.label} (${found.overlaps!.times}). '
                      'Everything from ${_start!} on moves ${found.roomNeeded} minutes later to make room.',
                    ),
                  )
                else if (found != null && day.isNotEmpty)
                  _Note(
                    key: const Key('break-fits'),
                    icon: Icons.check_circle_outline,
                    colour: colors.success,
                    text: 'Fits between your periods.',
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          onPressed: _isSubmitting || found?.startsDuring != null ? null : _submit,
          child: _isSubmitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Save'),
        ),
      ],
    );
  }

  /// Unticked on purpose: then saving tells them what it overlaps instead.
  bool _untickedByHand = false;

  Widget _timeBox(String label, String? value, VoidCallback onTap, Key key) {
    return InkWell(
      key: key,
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(labelText: label, isDense: true),
        child: Text(value ?? 'Select'),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({super.key, required this.icon, required this.colour, required this.text});

  final IconData icon;
  final Color colour;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colour),
        const SizedBox(width: 6),
        Expanded(
          child: Text(text, style: TextStyle(color: colour, fontSize: 13)),
        ),
      ],
    );
  }
}

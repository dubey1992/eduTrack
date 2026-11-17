import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../data/absence_notes.dart';

/// Beside a child on the register: their parent sent a note for the day
/// (docs/parent-student-app.md, F5). Tapping it shows the note and lets
/// whoever keeps the register acknowledge it. Never a mark - the register is
/// still marked as usual.
class AbsenceNoteChip extends StatelessWidget {
  const AbsenceNoteChip({super.key, required this.note, required this.studentName, this.onAcknowledged});

  final RegisterAbsenceNote note;
  final String studentName;

  /// Called once the note is acknowledged, so the register can show it.
  final VoidCallback? onAcknowledged;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return ActionChip(
      key: Key('absence-note-${note.id}'),
      avatar: Icon(Icons.mail_outline_rounded, size: 16, color: colours.onInfoContainer),
      label: Text(note.acknowledged ? 'Parent\'s note · seen' : 'Parent\'s note'),
      labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: colours.onInfoContainer),
      backgroundColor: colours.infoContainer,
      side: BorderSide.none,
      visualDensity: VisualDensity.compact,
      onPressed: () => showDialog<void>(
        context: context,
        builder: (_) => AbsenceNoteDialog(note: note, studentName: studentName, onAcknowledged: onAcknowledged),
      ),
    );
  }
}

class AbsenceNoteDialog extends ConsumerStatefulWidget {
  const AbsenceNoteDialog({super.key, required this.note, required this.studentName, this.onAcknowledged});

  final RegisterAbsenceNote note;
  final String studentName;
  final VoidCallback? onAcknowledged;

  @override
  ConsumerState<AbsenceNoteDialog> createState() => _AbsenceNoteDialogState();
}

class _AbsenceNoteDialogState extends ConsumerState<AbsenceNoteDialog> {
  bool _busy = false;
  String? _error;
  Uint8List? _photo;

  @override
  void initState() {
    super.initState();
    if (widget.note.hasPhoto) _loadPhoto();
  }

  Future<void> _loadPhoto() async {
    try {
      final bytes = await ref.read(absenceNotesRepositoryProvider).photo(widget.note.id);
      if (mounted) setState(() => _photo = Uint8List.fromList(bytes));
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    }
  }

  Future<void> _acknowledge() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(absenceNotesRepositoryProvider).acknowledge(widget.note.id);
      widget.onAcknowledged?.call();
      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Marked as seen. The parent can see that.')));
    } on Failure catch (failure) {
      if (mounted) setState(() => _error = failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return AlertDialog(
      title: Text('Note about ${widget.studentName}'),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.note.reason, style: const TextStyle(height: 1.4)),
              if (_photo != null) ...[
                const SizedBox(height: 12),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.memory(_photo!, key: const Key('absence-note-photo'), fit: BoxFit.contain),
                ),
              ],
              const SizedBox(height: 12),
              Text(
                'A note doesn\'t mark the register - mark it as usual.',
                style: TextStyle(fontSize: 13, color: colours.muted),
              ),
              if (_error != null) ...[
                const SizedBox(height: 8),
                Text(_error!, style: TextStyle(color: colours.danger, fontSize: 13)),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close')),
        if (!widget.note.acknowledged)
          FilledButton(
            key: const Key('absence-note-acknowledge'),
            onPressed: _busy ? null : _acknowledge,
            child: _busy
                ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Mark as seen'),
          ),
      ],
    );
  }
}

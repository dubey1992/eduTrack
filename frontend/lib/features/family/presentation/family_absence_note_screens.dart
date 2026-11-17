import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/utils/photo_picker.dart';
import '../../../core/utils/picked_file.dart';
import '../application/family_learning_notifiers.dart';
import '../application/family_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/family_repository.dart';
import '../data/models/family_absence_note.dart';
import 'widgets/family_widgets.dart';

/// The days a note may cover, counted from today - the server's rule too.
const maxNoteDaysAhead = 30;
const noteReasonMin = 10;
const noteReasonMax = 500;

String noteDays(DateTime start, DateTime end) =>
    start == end ? formatDate(start) : '${formatDate(start)} - ${formatDate(end)}';

/// A parent's absence notes for the child on screen (docs/parent-student-app.md,
/// F5), newest first, each sent or seen by the class teacher.
class FamilyAbsenceNotesScreen extends ConsumerWidget {
  const FamilyAbsenceNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(selectedChildProvider);

    return Scaffold(
      appBar: AppBar(title: Text(child == null ? 'Absence notes' : 'Absence notes for ${child.firstName}')),
      floatingActionButton: child == null
          ? null
          : FloatingActionButton.extended(
              key: const Key('family-new-note'),
              onPressed: () => context.push('/absence-notes/new'),
              icon: const Icon(Icons.edit_note_rounded),
              label: const Text('Tell the school'),
            ),
      body: child == null
          ? const FamilyEmptyView(icon: Icons.family_restroom_rounded, title: 'No children to show')
          : ref
                .watch(familyAbsenceNotesProvider(child.id))
                .when(
                  loading: () => const PlaceholderCards(count: 2),
                  error: (error, _) => FamilyErrorView(
                    error: error,
                    onRetry: () => ref.invalidate(familyAbsenceNotesProvider(child.id)),
                  ),
                  data: (notes) => notes.isEmpty
                      ? FamilyEmptyView(
                          icon: Icons.mark_email_read_outlined,
                          title: 'No notes sent',
                          message:
                              'If ${child.firstName} will be away, tell the school here - the class teacher sees it.',
                        )
                      : ListView(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                          children: [
                            for (final note in notes) ...[_NoteCard(note: note), const SizedBox(height: 10)],
                          ],
                        ),
                ),
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note});

  final FamilyAbsenceNote note;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;

    return FamilyCard(
      key: Key('family-note-${note.id}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  noteDays(note.startDate, note.endDate),
                  style: const TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: note.seen ? colours.successContainer : colours.infoContainer,
                  borderRadius: BorderRadius.circular(99),
                ),
                child: Text(
                  note.seen ? 'Seen by the class teacher' : 'Sent',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: note.seen ? colours.onSuccessContainer : colours.onInfoContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(note.reason),
          if (note.hasPhoto)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('With a photo of a note', style: TextStyle(fontSize: 13, color: colours.muted)),
            ),
        ],
      ),
    );
  }
}

/// "Tell the school your child will be away": the days, the reason, and if
/// there is one a photo of a doctor's note. Every rule the server keeps is
/// checked here first, so a parent learns what to fix before sending.
class FamilyNewAbsenceNoteScreen extends ConsumerStatefulWidget {
  const FamilyNewAbsenceNoteScreen({super.key});

  @override
  ConsumerState<FamilyNewAbsenceNoteScreen> createState() => _FamilyNewAbsenceNoteScreenState();
}

class _FamilyNewAbsenceNoteScreenState extends ConsumerState<FamilyNewAbsenceNoteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _reason = TextEditingController();
  late DateTime _start;
  late DateTime _end;
  PickedFile? _photo;
  bool _sending = false;

  /// What the school said, for a field or for the whole note.
  Map<String, String> _fieldErrors = {};
  String? _problem;

  DateTime get _today => ref.read(familyTodayDateProvider);

  @override
  void initState() {
    super.initState();
    _start = _today;
    _end = _today;
  }

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  Future<void> _pickDay({required bool first}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: first ? _start : _end,
      firstDate: first ? _today : _start,
      lastDate: _today.add(const Duration(days: maxNoteDaysAhead)),
      helpText: first ? 'First day away' : 'Last day away',
    );
    if (picked == null) return;

    setState(() {
      if (first) {
        _start = picked;
        if (_end.isBefore(picked)) _end = picked;
      } else {
        _end = picked;
      }
      _fieldErrors = {};
    });
  }

  Future<void> _pickPhoto() async {
    PhotoSource? source = PhotoSource.gallery;
    if (!kIsWeb) {
      source = await showModalBottomSheet<PhotoSource>(
        context: context,
        builder: (context) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                key: const Key('family-photo-camera'),
                leading: const Icon(Icons.photo_camera_outlined),
                title: const Text('Take a photo'),
                onTap: () => Navigator.of(context).pop(PhotoSource.camera),
              ),
              ListTile(
                key: const Key('family-photo-gallery'),
                leading: const Icon(Icons.photo_library_outlined),
                title: const Text('Choose from your photos'),
                onTap: () => Navigator.of(context).pop(PhotoSource.gallery),
              ),
            ],
          ),
        ),
      );
    }
    if (source == null) return;

    final picked = await ref.read(photoPickerProvider)(source);
    if (picked != null && mounted) setState(() => _photo = picked);
  }

  Future<void> _send() async {
    if (_sending || !_formKey.currentState!.validate()) return;
    final child = ref.read(selectedChildProvider);
    if (child == null) return;

    setState(() {
      _sending = true;
      _fieldErrors = {};
      _problem = null;
    });
    final messenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);

    try {
      await ref
          .read(familyRepositoryProvider)
          .sendAbsenceNote(
            child.id,
            start: _start,
            end: _end,
            reason: _reason.text.trim(),
            photo: _photo?.bytes,
            photoName: _photo?.name,
          );
      ref.invalidate(familyAbsenceNotesProvider(child.id));
      // Back to where they came from - or, opened straight from a link, to the list.
      if (router.canPop()) {
        router.pop();
      } else {
        router.go('/absence-notes');
      }
      messenger.showSnackBar(SnackBar(content: Text('Sent. ${child.firstName}\'s class teacher will see it.')));
    } on Failure catch (failure) {
      if (!mounted) return;
      setState(() {
        _fieldErrors = {for (final entry in failure.validationErrors.entries) entry.key: entry.value.first};
        _problem = _fieldErrors.isEmpty || failure.code == 'ABSENCE_NOTE_ALREADY_SENT' ? failure.message : null;
      });
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final child = ref.watch(selectedChildProvider);
    final colours = context.appColors;

    return Scaffold(
      appBar: AppBar(title: Text('${child?.firstName ?? 'Your child'} will be away')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          children: [
            Text(
              'The class teacher sees this on the register. It doesn\'t mark ${child?.firstName ?? 'your child'} '
              'absent by itself.',
              style: TextStyle(color: colours.muted),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _DayField(
                    key: const Key('family-note-start'),
                    label: 'First day',
                    day: _start,
                    error: _fieldErrors['start_date'],
                    onTap: () => _pickDay(first: true),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _DayField(
                    key: const Key('family-note-end'),
                    label: 'Last day',
                    day: _end,
                    error: _fieldErrors['end_date'],
                    onTap: () => _pickDay(first: false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextFormField(
              key: const Key('family-note-reason'),
              controller: _reason,
              minLines: 3,
              maxLines: 6,
              maxLength: noteReasonMax,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: 'Why will they be away?',
                hintText: 'e.g. Fever since last night - the doctor has advised two days\' rest.',
                errorText: _fieldErrors['reason'],
              ),
              validator: (value) {
                final length = (value ?? '').trim().length;
                if (length < noteReasonMin) return 'Please write a little more - at least $noteReasonMin characters.';
                return null;
              },
            ),
            const SizedBox(height: 8),
            _PhotoField(
              photo: _photo,
              error: _fieldErrors['photo'],
              onPick: _sending ? null : _pickPhoto,
              onRemove: _sending ? null : () => setState(() => _photo = null),
            ),
            if (_problem != null) ...[
              const SizedBox(height: 12),
              Container(
                key: const Key('family-note-problem'),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: colours.warningContainer, borderRadius: BorderRadius.circular(12)),
                child: Text(_problem!, style: TextStyle(color: colours.onWarningContainer)),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              key: const Key('family-note-send'),
              onPressed: _sending ? null : _send,
              child: _sending
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Send to the school'),
            ),
          ],
        ),
      ),
    );
  }
}

class _DayField extends StatelessWidget {
  const _DayField({super.key, required this.label, required this.day, required this.onTap, this.error});

  final String label;
  final DateTime day;
  final VoidCallback onTap;
  final String? error;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          errorText: error,
          errorMaxLines: 3,
          suffixIcon: const Icon(Icons.calendar_today_rounded, size: 18),
        ),
        child: Text(formatDate(day)),
      ),
    );
  }
}

class _PhotoField extends StatelessWidget {
  const _PhotoField({required this.photo, required this.onPick, required this.onRemove, this.error});

  final PickedFile? photo;
  final VoidCallback? onPick;
  final VoidCallback? onRemove;
  final String? error;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final photo = this.photo;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (photo == null)
          OutlinedButton.icon(
            key: const Key('family-note-add-photo'),
            onPressed: onPick,
            icon: const Icon(Icons.add_a_photo_outlined, size: 18),
            label: const Text('Add a photo of a doctor\'s note (optional)'),
          )
        else
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.memory(
                  Uint8List.fromList(photo.bytes),
                  key: const Key('family-note-photo'),
                  width: 64,
                  height: 64,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => Container(
                    width: 64,
                    height: 64,
                    color: colours.infoContainer,
                    child: const Icon(Icons.image_outlined),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Text(photo.name, overflow: TextOverflow.ellipsis)),
              TextButton(key: const Key('family-note-remove-photo'), onPressed: onRemove, child: const Text('Remove')),
            ],
          ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(error!, style: TextStyle(color: colours.danger, fontSize: 12)),
          ),
      ],
    );
  }
}

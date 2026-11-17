import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_colors.dart';
import '../../../core/utils/date_format.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/section_header.dart';
import '../application/absence_notes_notifier.dart';
import '../data/absence_notes.dart';
import 'absence_note_chip.dart';

/// Parents' absence notes (docs/parent-student-app.md, F5): the ones nobody
/// has seen yet first, each with its days, reason, the parent who sent it and
/// any photo of a doctor's note; "Mark as seen" tells the parent the school
/// has it. A teacher sees the classes they keep the register of.
class AbsenceNotesScreen extends ConsumerWidget {
  const AbsenceNotesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(absenceNotesFilterProvider);
    final notes = ref.watch(absenceNotesProvider);

    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        SectionHeader(
          title: 'Absence Notes',
          actions: [
            SegmentedButton<bool>(
              key: const Key('absence-notes-filter'),
              segments: const [
                ButtonSegment(value: true, label: Text('Not seen yet')),
                ButtonSegment(value: false, label: Text('Seen')),
              ],
              selected: {filter.unseen},
              onSelectionChanged: (choice) => ref.read(absenceNotesFilterProvider.notifier).show(unseen: choice.first),
            ),
          ],
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Text(
            'Parents tell the school here when their child will be away. A note never marks the register.',
            style: TextStyle(color: context.appColors.muted),
          ),
        ),
        const SizedBox(height: 12),
        AsyncValueView(
          value: notes,
          onRetry: () => ref.invalidate(absenceNotesProvider),
          isEmpty: (page) => page.items.isEmpty,
          emptyBuilder: (context) => Padding(
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text(
                filter.unseen ? 'No new notes from parents.' : 'No notes have been marked as seen yet.',
                style: TextStyle(color: context.appColors.muted),
              ),
            ),
          ),
          data: (context, page) => Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                for (final note in page.items) ...[
                  _NoteCard(note: note, onSeen: () => ref.invalidate(absenceNotesProvider)),
                  const SizedBox(height: 10),
                ],
                if (page.lastPage > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      Text('Page ${page.currentPage} of ${page.lastPage}'),
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: page.currentPage > 1
                            ? () => ref.read(absenceNotesFilterProvider.notifier).goTo(page.currentPage - 1)
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: page.currentPage < page.lastPage
                            ? () => ref.read(absenceNotesFilterProvider.notifier).goTo(page.currentPage + 1)
                            : null,
                        icon: const Icon(Icons.chevron_right),
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _NoteCard extends StatelessWidget {
  const _NoteCard({required this.note, required this.onSeen});

  final StaffAbsenceNote note;
  final VoidCallback onSeen;

  @override
  Widget build(BuildContext context) {
    final colours = context.appColors;
    final days = note.startDate == note.endDate
        ? formatDate(note.startDate)
        : '${formatDate(note.startDate)} - ${formatDate(note.endDate)}';

    return Card(
      key: Key('absence-note-card-${note.id}'),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(note.studentName, style: Theme.of(context).textTheme.titleMedium),
                  Text(days, style: TextStyle(color: colours.muted)),
                  const SizedBox(height: 6),
                  Text(note.reason),
                  const SizedBox(height: 6),
                  Text(
                    note.acknowledged
                        ? 'From ${note.sentBy} · seen by ${note.acknowledgedBy ?? 'the school'}'
                        : 'From ${note.sentBy}${note.hasPhoto ? ' · with a photo of a note' : ''}',
                    style: TextStyle(fontSize: 13, color: colours.muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            OutlinedButton(
              key: Key('absence-note-open-${note.id}'),
              onPressed: () => showDialog<void>(
                context: context,
                builder: (_) => AbsenceNoteDialog(
                  note: RegisterAbsenceNote(
                    id: note.id,
                    reason: note.reason,
                    acknowledged: note.acknowledged,
                    hasPhoto: note.hasPhoto,
                  ),
                  studentName: note.studentName,
                  onAcknowledged: onSeen,
                ),
              ),
              child: Text(note.acknowledged ? 'Open' : 'Open and mark as seen'),
            ),
          ],
        ),
      ),
    );
  }
}

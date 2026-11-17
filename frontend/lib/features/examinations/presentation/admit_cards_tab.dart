import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/utils/file_saver.dart';
import '../../../core/widgets/async_value_view.dart';
import '../../../core/widgets/status_badge.dart';
import '../../classes/data/models/school_class.dart';
import '../application/examination_providers.dart';
import '../data/examination_repository.dart';
import '../data/models/examination.dart';

/// Hands a PDF to the browser to save. Swappable in tests, where there is no
/// browser.
typedef PdfSaver = void Function(String fileName, List<int> bytes);

final admitCardSaverProvider = Provider<PdfSaver>(
  (ref) =>
      (fileName, bytes) => saveBytes(fileName: fileName, bytes: bytes, mimeType: 'application/pdf'),
);

/// Who sits the exam, and each one's admit card (docs/examinations.md).
///
/// A card's state is the server's: published or not, a paper for the class,
/// withheld by name, or held for overdue fees. Staff read the reason a card
/// is withheld and what is overdue; parents never do.
class AdmitCardsTab extends ConsumerStatefulWidget {
  const AdmitCardsTab({super.key, required this.exam, required this.canManage});

  final Examination exam;
  final bool canManage;

  @override
  ConsumerState<AdmitCardsTab> createState() => _AdmitCardsTabState();
}

class _AdmitCardsTabState extends ConsumerState<AdmitCardsTab> {
  final _search = TextEditingController();

  /// The version single cards download at; null for the latest.
  int? _version;
  bool _printing = false;

  Examination get exam => widget.exam;

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  CandidateFilter get _filter => ref.read(candidateFilterProvider(exam.id));

  void _setFilter(CandidateFilter filter) => ref.read(candidateFilterProvider(exam.id).notifier).set(filter);

  void _say(String message) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  String _problem(Object error) => error is Failure ? error.message : 'Something went wrong. Try again.';

  Future<void> _download(ExamCandidate candidate, {bool draft = false}) async {
    try {
      final bytes = await ref
          .read(examinationRepositoryProvider)
          .card(exam.id, candidate.studentId, draft: draft, version: draft ? null : _version);
      final who = candidate.admissionNumber.isEmpty ? '${candidate.studentId}' : candidate.admissionNumber;
      ref.read(admitCardSaverProvider)('admit-card-$who.pdf', bytes);
    } catch (error) {
      _say(_problem(error));
    }
  }

  Future<void> _printSection(int sectionId) async {
    if (_printing) return;
    setState(() => _printing = true);
    try {
      final batch = await ref.read(examinationRepositoryProvider).sectionCards(exam.id, sectionId: sectionId);
      ref.read(admitCardSaverProvider)(batch.fileName, batch.bytes);
      _say(
        batch.skipped == 0
            ? '${batch.printed} card${batch.printed == 1 ? '' : 's'} ready to print.'
            : '${batch.printed} card${batch.printed == 1 ? '' : 's'} ready to print. ${batch.skipped} left out - '
                  'withheld, held for fees, or not ready.',
      );
    } catch (error) {
      _say(_problem(error));
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }

  Future<void> _setException(ExamCandidate candidate, String? kind) async {
    String? reason;

    if (kind != null) {
      reason = await showDialog<String>(
        context: context,
        builder: (_) => _ReasonDialog(
          title: kind == 'withhold' ? 'Withhold ${candidate.name}\'s card' : 'Let ${candidate.name} through',
          hint: kind == 'withhold'
              ? 'Why it is withheld. Staff see this; parents only read "contact the school".'
              : 'Why the card is issued despite overdue fees (optional).',
          required: kind == 'withhold',
          confirmLabel: kind == 'withhold' ? 'Withhold card' : 'Issue the card',
        ),
      );
      if (reason == null) return;
    }

    try {
      await ref
          .read(examinationRepositoryProvider)
          .setException(exam.id, studentId: candidate.studentId, kind: kind, reason: reason);
      ref.invalidate(candidatesProvider(exam.id));
      _say(switch (kind) {
        'withhold' => '${candidate.name}\'s card is withheld.',
        'allow' => '${candidate.name}\'s card will be issued.',
        _ => '${candidate.name}\'s card follows the exam\'s rules again.',
      });
    } catch (error) {
      _say(_problem(error));
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = ref.watch(candidateFilterProvider(exam.id));
    final page = ref.watch(candidatesProvider(exam.id));
    final classes = ref.watch(examClassesProvider(exam.academicYearId)).value ?? const <SchoolClass>[];
    final sections = [
      for (final c in classes)
        if (exam.papers.any((paper) => paper.schoolClassId == c.id))
          for (final section in c.sections) (id: section.id, label: '${c.name} - ${section.name}'),
    ];
    final colors = context.appColors;
    final counts = page.value?.counts ?? const <CardState, int>{};

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 14, 20, 6),
          child: Wrap(
            spacing: 12,
            runSpacing: 10,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 200,
                child: DropdownButtonFormField<int?>(
                  key: const Key('cards-section'),
                  initialValue: filter.sectionId,
                  isExpanded: true,
                  decoration: const InputDecoration(labelText: 'Section', isDense: true),
                  items: [
                    const DropdownMenuItem<int?>(value: null, child: Text('All sections')),
                    for (final section in sections)
                      DropdownMenuItem<int?>(value: section.id, child: Text(section.label)),
                  ],
                  onChanged: (value) => _setFilter(_filter.copyWith(sectionId: () => value)),
                ),
              ),
              SizedBox(
                width: 220,
                child: TextField(
                  key: const Key('cards-search'),
                  controller: _search,
                  decoration: const InputDecoration(
                    labelText: 'Search name or admission no.',
                    isDense: true,
                    prefixIcon: Icon(Icons.search, size: 18),
                  ),
                  onSubmitted: (value) => _setFilter(_filter.copyWith(query: value)),
                ),
              ),
              if (exam.versions.length > 1)
                SizedBox(
                  width: 190,
                  child: DropdownButtonFormField<int?>(
                    key: const Key('cards-version'),
                    initialValue: _version,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Print version', isDense: true),
                    items: [
                      for (final version in exam.versions)
                        DropdownMenuItem<int?>(
                          value: version == exam.versions.first ? null : version.version,
                          child: Text('Version ${version.version} (${version.publishedOn})'),
                        ),
                    ],
                    onChanged: (value) => setState(() => _version = value),
                  ),
                ),
              FilledButton.icon(
                key: const Key('cards-print-section'),
                onPressed: filter.sectionId == null || !exam.isPublished || _printing
                    ? null
                    : () => _printSection(filter.sectionId!),
                icon: const Icon(Icons.print_outlined, size: 18),
                label: const Text('Print section'),
              ),
            ],
          ),
        ),
        if (!exam.isPublished)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              widget.canManage
                  ? 'Not published yet: cards cannot be issued. You can preview a draft card from a student\'s row.'
                  : 'Not published yet.',
              key: const Key('cards-not-published'),
              style: TextStyle(color: colors.warning, fontSize: 13),
            ),
          ),
        if (filter.sectionId == null && exam.isPublished)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Text(
              'Choose a section to print all its ready cards at once, one per sheet.',
              style: TextStyle(color: colors.muted, fontSize: 13),
            ),
          ),
        if (counts.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
            child: Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                ChoiceChip(
                  label: Text('All (${counts.values.fold(0, (a, b) => a + b)})'),
                  selected: filter.state == null,
                  onSelected: (_) => _setFilter(_filter.copyWith(state: () => null)),
                ),
                for (final entry in counts.entries)
                  ChoiceChip(
                    key: Key('cards-state-${entry.key.apiValue}'),
                    label: Text('${entry.key.label} (${entry.value})'),
                    selected: filter.state == entry.key,
                    onSelected: (_) => _setFilter(_filter.copyWith(state: () => entry.key)),
                  ),
              ],
            ),
          ),
        Expanded(
          child: AsyncValueView<CandidatePage>(
            value: page,
            onRetry: () => ref.invalidate(candidatesProvider(exam.id)),
            isEmpty: (data) => data.items.isEmpty,
            emptyBuilder: (context) => Center(
              key: const Key('cards-empty'),
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  exam.paperCount == 0
                      ? 'Add papers to the date sheet first: students are listed by the classes it covers.'
                      : 'No students match.',
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (context, data) => ListView(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
              children: [
                for (final candidate in data.items) _row(candidate),
                if (data.lastPage > 1)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      IconButton(
                        tooltip: 'Previous page',
                        onPressed: data.currentPage > 1
                            ? () => _setFilter(
                                CandidateFilter(
                                  sectionId: filter.sectionId,
                                  query: filter.query,
                                  state: filter.state,
                                  page: data.currentPage - 1,
                                ),
                              )
                            : null,
                        icon: const Icon(Icons.chevron_left),
                      ),
                      Text('Page ${data.currentPage} of ${data.lastPage}'),
                      IconButton(
                        tooltip: 'Next page',
                        onPressed: data.currentPage < data.lastPage
                            ? () => _setFilter(
                                CandidateFilter(
                                  sectionId: filter.sectionId,
                                  query: filter.query,
                                  state: filter.state,
                                  page: data.currentPage + 1,
                                ),
                              )
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

  Widget _row(ExamCandidate candidate) {
    final colors = context.appColors;
    final tone = switch (candidate.state) {
      CardState.ready => BadgeTone.success,
      CardState.withheld || CardState.feeHold => BadgeTone.warning,
      _ => BadgeTone.neutral,
    };
    final detail = [
      if (candidate.reason != null) 'Reason: ${candidate.reason}',
      if (candidate.overdue != null) 'Overdue: ${candidate.overdue}',
      if (candidate.exception == 'allow') 'Let through the fee hold',
      if (candidate.missing.isNotEmpty) 'Missing: ${candidate.missing.join(', ')}',
    ];

    return Card(
      key: Key('candidate-${candidate.studentId}'),
      margin: const EdgeInsets.only(bottom: 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(candidate.name, style: const TextStyle(fontWeight: FontWeight.w600)),
                      StatusBadge(label: candidate.state.label, tone: tone),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    [
                      candidate.admissionNumber,
                      candidate.classLabel,
                      if (candidate.rollNumber != null) 'Roll ${candidate.rollNumber}',
                    ].join(' · '),
                    style: TextStyle(color: colors.muted, fontSize: 13),
                  ),
                  if (detail.isNotEmpty)
                    Text(detail.join(' · '), style: TextStyle(color: colors.warning, fontSize: 12)),
                ],
              ),
            ),
            if (candidate.state == CardState.ready)
              IconButton(
                key: Key('candidate-card-${candidate.studentId}'),
                tooltip: 'Download admit card',
                icon: const Icon(Icons.download_outlined),
                onPressed: () => _download(candidate),
              )
            else if (widget.canManage && candidate.state == CardState.notPublished)
              TextButton(
                key: Key('candidate-draft-${candidate.studentId}'),
                onPressed: () => _download(candidate, draft: true),
                child: const Text('Preview draft'),
              ),
            if (widget.canManage && exam.isPublished)
              PopupMenuButton<String>(
                key: Key('candidate-menu-${candidate.studentId}'),
                tooltip: 'Hold or release',
                onSelected: (choice) => _setException(candidate, choice == 'none' ? null : choice),
                itemBuilder: (_) => [
                  if (candidate.exception != 'withhold')
                    const PopupMenuItem(value: 'withhold', child: Text('Withhold card')),
                  if (exam.blockOnFeeDues && candidate.exception != 'allow')
                    const PopupMenuItem(value: 'allow', child: Text('Issue despite overdue fees')),
                  if (candidate.exception != null)
                    const PopupMenuItem(value: 'none', child: Text('Back to the exam\'s rules')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class _ReasonDialog extends StatefulWidget {
  const _ReasonDialog({required this.title, required this.hint, required this.required, required this.confirmLabel});

  final String title;
  final String hint;
  final bool required;
  final String confirmLabel;

  @override
  State<_ReasonDialog> createState() => _ReasonDialogState();
}

class _ReasonDialogState extends State<_ReasonDialog> {
  final _reason = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _reason.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      content: SizedBox(
        width: 420,
        child: TextField(
          key: const Key('cards-reason'),
          controller: _reason,
          maxLength: 255,
          minLines: 2,
          maxLines: 4,
          decoration: InputDecoration(
            labelText: 'Reason',
            helperText: widget.hint,
            helperMaxLines: 3,
            errorText: _error,
          ),
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Cancel')),
        FilledButton(
          key: const Key('cards-reason-save'),
          onPressed: () {
            final text = _reason.text.trim();
            if (widget.required && text.isEmpty) {
              setState(() => _error = 'Say why the card is withheld.');
              return;
            }
            Navigator.of(context).pop(text);
          },
          child: Text(widget.confirmLabel),
        ),
      ],
    );
  }
}

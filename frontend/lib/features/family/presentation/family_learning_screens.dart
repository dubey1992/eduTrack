import 'widgets/saved_copy_line.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/failure.dart';
import '../../../core/theme/app_colors.dart';
import '../../../core/theme/family_brand.dart';
import '../../../core/utils/date_format.dart';
import '../application/family_learning_notifiers.dart';
import '../application/family_session_notifier.dart';
import '../data/family_repository.dart';
import '../data/models/family_account.dart';
import '../data/models/family_learning.dart';
import '../data/models/family_homework.dart';
import '../../../core/utils/pdf_hand_off.dart';
import 'widgets/family_widgets.dart';
import 'widgets/marks_trend.dart';

/// A learning screen's frame: a back arrow, its title, and whose it is.
class _LearningScaffold extends ConsumerWidget {
  const _LearningScaffold({required this.title, required this.body});

  final String title;
  final Widget Function(FamilyChild child) body;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final child = ref.watch(selectedChildProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title),
            if (child != null) Text(child.fullName, style: TextStyle(fontSize: 12, color: context.appColors.muted)),
          ],
        ),
      ),
      body: child == null
          ? const FamilyEmptyView(icon: Icons.family_restroom_rounded, title: 'No children to show')
          : body(child),
    );
  }
}

/// A mark's colour: red only below the school's own line for a weak result,
/// the ordinary text colour otherwise - a "B" is not a failure and is not
/// painted like one, and no line is invented here that the school did not set.
Color? _markColour(BuildContext context, String? percent, double weakBelow) {
  final value = double.tryParse(percent ?? '');
  if (value == null) return context.appColors.muted;
  return value < weakBelow ? context.appColors.danger : null;
}

// -- Results ------------------------------------------------------------------------

class FamilyResultsScreen extends ConsumerStatefulWidget {
  const FamilyResultsScreen({super.key});

  @override
  ConsumerState<FamilyResultsScreen> createState() => _FamilyResultsScreenState();
}

class _FamilyResultsScreenState extends ConsumerState<FamilyResultsScreen> {
  /// The term chosen, or null for the one being lived.
  int? _termId;
  bool _downloading = false;

  Future<void> _download(FamilyChild child, SchoolTerm term) async {
    if (_downloading) return;
    setState(() => _downloading = true);
    final messenger = ScaffoldMessenger.of(context);

    try {
      final bytes = await ref.read(familyRepositoryProvider).progressReport(child.id, termId: term.id);
      final name =
          'progress-report-${child.firstName.toLowerCase()}-${term.name.toLowerCase().replaceAll(' ', '-')}.pdf';
      await ref.read(pdfHandOffProvider)(bytes, name);
    } on Failure catch (failure) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    } finally {
      if (mounted) setState(() => _downloading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return _LearningScaffold(
      title: 'Results',
      body: (child) {
        final key = (child.id, _termId);
        return ref
            .watch(familyResultsProvider(key))
            .when(
              loading: () => const PlaceholderCards(),
              error: (error, _) =>
                  FamilyErrorView(error: error, onRetry: () => ref.read(familyResultsProvider(key).notifier).refresh()),
              data: (results) => RefreshIndicator(
                onRefresh: () => ref.read(familyResultsProvider(key).notifier).refresh(),
                child: ListView(
                  key: const Key('family-results'),
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    SavedCopyLine(name: 'results:${child.id}:${key.$2 ?? 'current'}'),
                    if (results.terms.length > 1) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final term in results.terms.reversed)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: ChoiceChip(
                                  key: Key('family-term-${term.id}'),
                                  label: Text(term.name),
                                  selected: term.id == results.term?.id,
                                  onSelected: (_) => setState(() => _termId = term.id),
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    if (results.term == null)
                      const FamilyEmptyView(
                        icon: Icons.grade_outlined,
                        title: 'No terms yet',
                        message: 'Results appear here once the school sets up its terms.',
                      )
                    else ...[
                      _ReportCard(
                        term: results.term!,
                        available: results.reportAvailable,
                        from: results.reportFrom,
                        busy: _downloading,
                        onDownload: () => _download(child, results.term!),
                      ),
                      if (results.remark != null) ...[
                        const SizedBox(height: 12),
                        FamilyCard(
                          key: const Key('family-remark'),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const CardHeading(icon: Icons.format_quote_rounded, title: 'From the class teacher'),
                              const SizedBox(height: 10),
                              Text(results.remark!, style: const TextStyle(height: 1.4)),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 12),
                      if (results.subjects.isEmpty)
                        const Padding(
                          padding: EdgeInsets.only(top: 24),
                          child: FamilyEmptyView(
                            icon: Icons.grade_outlined,
                            title: 'No results yet this term',
                            message: 'A test appears here once the teacher publishes its marks.',
                          ),
                        )
                      else ...[
                        for (final subject in results.subjects) ...[
                          _SubjectCard(
                            subject: subject,
                            showsAverage: results.showsClassAverage,
                            weakBelow: results.weakBelow,
                          ),
                          const SizedBox(height: 12),
                        ],
                        const HowWorkedOut(
                          key: Key('family-why-results'),
                          explanation:
                              "Each subject's figure is the average of its published test marks this term, as "
                              'percentages - weighted when the school gave every test a weight. A test the child '
                              "missed is left out. The grade comes from the school's own grading scale.",
                        ),
                      ],
                    ],
                  ],
                ),
              ),
            );
      },
    );
  }
}

class _ReportCard extends StatelessWidget {
  const _ReportCard({
    required this.term,
    required this.available,
    required this.from,
    required this.busy,
    required this.onDownload,
  });

  final SchoolTerm term;
  final bool available;
  final DateTime? from;
  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    return FamilyCard(
      key: const Key('family-progress-report'),
      child: Row(
        children: [
          Icon(Icons.picture_as_pdf_rounded, color: available ? context.appColors.danger : context.appColors.muted),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${term.name} progress report', style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  available
                      ? 'Open it, save it or share it.'
                      : 'Ready when the term ends${from == null ? '' : ', on ${formatDate(from!)}'}.',
                  style: TextStyle(color: context.appColors.muted, fontSize: 13),
                ),
              ],
            ),
          ),
          if (available)
            FilledButton(
              key: const Key('family-download-report'),
              onPressed: busy ? null : onDownload,
              child: busy
                  ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Get PDF'),
            ),
        ],
      ),
    );
  }
}

class _SubjectCard extends StatelessWidget {
  const _SubjectCard({required this.subject, required this.showsAverage, required this.weakBelow});

  final SubjectResults subject;
  final bool showsAverage;
  final double weakBelow;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final colour = _markColour(context, subject.average, weakBelow);

    return FamilyCard(
      key: Key('family-subject-${subject.subject}'),
      padding: EdgeInsets.zero,
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          shape: const RoundedRectangleBorder(),
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          title: Text(subject.subject, style: const TextStyle(fontWeight: FontWeight.w700)),
          subtitle: Text(
            [
              '${subject.tests.length} ${subject.tests.length == 1 ? 'test' : 'tests'}',
              if (showsAverage && subject.classAverage != null) 'class ${readableNumber(subject.classAverage)}%',
            ].join(' · '),
            style: TextStyle(color: muted, fontSize: 13),
          ),
          trailing: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                subject.average == null ? '-' : '${readableNumber(subject.average)}%',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, color: colour),
              ),
              if (subject.grade != null) Text('Grade ${subject.grade}', style: TextStyle(color: muted, fontSize: 12)),
            ],
          ),
          children: [
            // How the marks have moved, test by test (M8, 8.2).
            MarksTrend(tests: subject.tests, weakBelow: weakBelow),
            for (final test in subject.tests) _TestRow(test: test, showsAverage: showsAverage, weakBelow: weakBelow),
          ],
        ),
      ),
    );
  }
}

class _TestRow extends StatelessWidget {
  const _TestRow({required this.test, required this.showsAverage, required this.weakBelow});

  final TestResult test;
  final bool showsAverage;
  final double weakBelow;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;

    return Padding(
      key: Key('family-test-${test.id}'),
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(test.title, style: const TextStyle(fontWeight: FontWeight.w600)),
                Text(
                  [
                    if (test.date != null) formatDate(test.date!),
                    if (showsAverage && test.classAverage != null)
                      'class average ${readableNumber(test.classAverage)}%',
                  ].join(' · '),
                  style: TextStyle(color: muted, fontSize: 12),
                ),
                if (test.remarks != null) Text(test.remarks!, style: TextStyle(color: muted, fontSize: 12)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                test.score,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  color: test.isAbsent ? context.appColors.warning : _markColour(context, test.percentage, weakBelow),
                ),
              ),
              if (test.grade != null) Text(test.grade!, style: TextStyle(color: muted, fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}

// -- Timetable ------------------------------------------------------------------------

class FamilyTimetableScreen extends ConsumerStatefulWidget {
  const FamilyTimetableScreen({super.key});

  @override
  ConsumerState<FamilyTimetableScreen> createState() => _FamilyTimetableScreenState();
}

class _FamilyTimetableScreenState extends ConsumerState<FamilyTimetableScreen> {
  String? _day;

  @override
  Widget build(BuildContext context) {
    return _LearningScaffold(
      title: 'Timetable',
      body: (child) => ref
          .watch(familyWeekProvider(child.id))
          .when(
            loading: () => const PlaceholderCards(),
            error: (error, _) =>
                FamilyErrorView(error: error, onRetry: () => ref.read(familyWeekProvider(child.id).notifier).refresh()),
            data: (week) {
              if (week.days.every((day) => day.periods.isEmpty)) {
                return const FamilyEmptyView(
                  icon: Icons.schedule_rounded,
                  title: 'No timetable yet',
                  message: 'The class\'s timetable appears here once the school sets it.',
                );
              }

              final days = week.days;
              final chosen = days.where((d) => d.day == (_day ?? week.today)).firstOrNull ?? days.first;

              return Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: SavedCopyLine(name: 'timetable:${child.id}'),
                  ),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    child: Row(
                      children: [
                        for (final day in days)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: ChoiceChip(
                              key: Key('family-day-${day.day}'),
                              label: Text(day.day == week.today ? '${day.shortLabel} · today' : day.shortLabel),
                              selected: day.day == chosen.day,
                              onSelected: (_) => setState(() => _day = day.day),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(child: _DayList(day: chosen)),
                ],
              );
            },
          ),
    );
  }
}

class _DayList extends StatelessWidget {
  const _DayList({required this.day});

  final SchoolDay day;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    // Periods and breaks in the order the bells ring.
    final rows = <(String, Widget)>[
      for (final period in day.periods)
        (
          period.startTime,
          ListTile(
            leading: SizedBox(
              width: 64,
              child: Text(formatClock(period.startTime), style: TextStyle(color: muted, fontSize: 13)),
            ),
            title: Text(period.subject ?? 'Free period', style: const TextStyle(fontWeight: FontWeight.w600)),
            subtitle: period.teacher == null ? null : Text(period.teacher!),
          ),
        ),
      for (final pause in day.breaks)
        (
          pause.startTime,
          ListTile(
            dense: true,
            leading: SizedBox(
              width: 64,
              child: Text(formatClock(pause.startTime), style: TextStyle(color: muted, fontSize: 13)),
            ),
            title: Text(
              pause.name,
              style: TextStyle(color: muted, fontStyle: FontStyle.italic),
            ),
          ),
        ),
    ]..sort((a, b) => a.$1.compareTo(b.$1));

    return ListView(
      key: Key('family-day-list-${day.day}'),
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        if (day.isHalfDay)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${day.label} is a half day.', style: TextStyle(color: muted)),
          ),
        if (day.periods.isEmpty)
          Text('No classes on ${day.label}.', style: TextStyle(color: muted))
        else
          FamilyCard(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Column(children: [for (final row in rows) row.$2]),
          ),
      ],
    );
  }
}

// -- Syllabus ------------------------------------------------------------------------

class FamilySyllabusScreen extends ConsumerWidget {
  const FamilySyllabusScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _LearningScaffold(
      title: 'Syllabus',
      body: (child) => ref
          .watch(familySyllabusProvider(child.id))
          .when(
            loading: () => const PlaceholderCards(),
            error: (error, _) => FamilyErrorView(
              error: error,
              onRetry: () => ref.read(familySyllabusProvider(child.id).notifier).refresh(),
            ),
            data: (subjects) => subjects.isEmpty
                ? const FamilyEmptyView(
                    icon: Icons.menu_book_rounded,
                    title: 'No syllabus yet',
                    message: 'What the class will cover appears here once the school adds it.',
                  )
                : ListView.separated(
                    key: const Key('family-syllabus'),
                    padding: const EdgeInsets.all(16),
                    itemCount: subjects.length + 1,
                    separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 0 : 12),
                    itemBuilder: (context, index) => index == 0
                        ? SavedCopyLine(name: 'syllabus:${child.id}')
                        : _SyllabusCard(subject: subjects[index - 1], index: index - 1),
                  ),
          ),
    );
  }
}

/// The class's homework, day by day, newest first (M8, 8.1): what the
/// teachers wrote in their teaching reports.
class FamilyHomeworkScreen extends ConsumerWidget {
  const FamilyHomeworkScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return _LearningScaffold(
      title: 'Homework',
      body: (child) => ref
          .watch(familyHomeworkProvider(child.id))
          .when(
            loading: () => const PlaceholderCards(),
            error: (error, _) => FamilyErrorView(
              error: error,
              onRetry: () => ref.read(familyHomeworkProvider(child.id).notifier).refresh(),
            ),
            data: (days) => days.isEmpty
                ? const FamilyEmptyView(
                    icon: Icons.edit_note_rounded,
                    title: 'No homework in the last two weeks',
                    message: 'When a teacher sets homework for the class, it appears here that day.',
                  )
                : ListView.separated(
                    key: const Key('family-homework'),
                    padding: const EdgeInsets.all(16),
                    itemCount: days.length + 1,
                    separatorBuilder: (_, index) => SizedBox(height: index == 0 ? 0 : 12),
                    itemBuilder: (context, index) => index == 0
                        ? SavedCopyLine(name: 'homework:${child.id}')
                        : _HomeworkDayCard(day: days[index - 1]),
                  ),
          ),
    );
  }
}

class _HomeworkDayCard extends StatelessWidget {
  const _HomeworkDayCard({required this.day});

  final HomeworkDay day;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;

    return FamilyCard(
      key: Key('family-homework-${day.date}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            day.today ? 'Today - ${day.dateLabel}' : day.dateLabel,
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          for (final item in day.items) ...[
            const SizedBox(height: 10),
            Text(
              item.subject ?? 'Homework',
              style: TextStyle(color: muted, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 2),
            Text(item.homework),
          ],
        ],
      ),
    );
  }
}

class _SyllabusCard extends StatelessWidget {
  const _SyllabusCard({required this.subject, required this.index});

  final SubjectSyllabus subject;
  final int index;

  @override
  Widget build(BuildContext context) {
    final muted = context.appColors.muted;
    final colour = FamilyBrand.childColour(index);

    return FamilyCard(
      key: Key('family-syllabus-${subject.subject}'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(subject.subject, style: const TextStyle(fontWeight: FontWeight.w700)),
              ),
              Text(
                '${subject.percent}%',
                style: TextStyle(fontWeight: FontWeight.w700, color: colour),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: subject.total == 0 ? 0 : subject.covered / subject.total,
              minHeight: 8,
              color: colour,
              backgroundColor: colour.withValues(alpha: 0.15),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subject.total == 0 ? 'No topics added yet.' : '${subject.covered} of ${subject.total} topics covered',
            style: TextStyle(color: muted, fontSize: 13),
          ),
          if (subject.nextTopics.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text('Coming up: ${subject.nextTopics.join(', ')}', style: TextStyle(color: muted, fontSize: 12)),
          ],
        ],
      ),
    );
  }
}

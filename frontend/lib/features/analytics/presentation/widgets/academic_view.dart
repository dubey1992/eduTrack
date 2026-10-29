import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_colors.dart';
import '../../../../core/widgets/async_value_view.dart';
import '../../../../core/widgets/horizontal_scroll_table.dart';
import '../../application/analytics_notifier.dart';
import '../../data/models/academic_overview.dart';

/// "Subjects & classes" on the Analytics page (docs/analytics.md, A4): each
/// subject and each class, term by term through one year, and every class's
/// subject beneath.
///
/// The colours are the school's own lines, not ours: a figure under the pass
/// mark reads as danger, one under the weak line as a warning, and the
/// legend says which numbers those are.
class AcademicView extends ConsumerStatefulWidget {
  const AcademicView({super.key, required this.schoolId});

  final int? schoolId;

  @override
  ConsumerState<AcademicView> createState() => _AcademicViewState();
}

class _AcademicViewState extends ConsumerState<AcademicView> {
  int? _yearId;

  @override
  Widget build(BuildContext context) {
    final query = (schoolId: widget.schoolId, academicYearId: _yearId);

    return AsyncValueView<AcademicOverview>(
      value: ref.watch(academicOverviewProvider(query)),
      onRetry: () => ref.invalidate(academicOverviewProvider(query)),
      data: (context, overview) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(overview: overview, onYear: (id) => setState(() => _yearId = id)),
          const SizedBox(height: 12),
          if (overview.yearId == null)
            const _Notice('No academic year has been set up yet.')
          else if (overview.termsSetUp == 0)
            const _Notice(
              'This year has no terms yet. A School Admin adds them under Academic Years, and results are then '
              'shown term by term.',
            )
          else if (overview.terms.isEmpty)
            const _Notice('No term of this year has begun yet.')
          else if (overview.isEmpty)
            const _Notice('No class test results have been published this year yet.')
          else ...[
            _LinesCard(title: 'By subject', overview: overview, lines: overview.subjects, firstColumn: 'Subject'),
            const SizedBox(height: 16),
            _LinesCard(title: 'By class', overview: overview, lines: overview.classes, firstColumn: 'Class'),
            const SizedBox(height: 16),
            _LinesCard(
              title: 'Each class, by subject',
              overview: overview,
              lines: overview.cells,
              firstColumn: 'Class',
              detailColumn: 'Subject',
              showBelow: true,
            ),
          ],
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.overview, required this.onYear});

  final AcademicOverview overview;
  final ValueChanged<int?> onYear;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Wrap(
      spacing: 16,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (overview.years.isNotEmpty)
          SizedBox(
            width: 240,
            child: DropdownButtonFormField<int>(
              initialValue: overview.yearId,
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Academic year', isDense: true),
              items: [
                for (final year in overview.years)
                  DropdownMenuItem(
                    value: year.id,
                    child: Text(
                      year.isCurrent ? '${year.name} (current)' : year.name,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                    ),
                  ),
              ],
              onChanged: onYear,
            ),
          ),
        Text(
          [
            'Average test score of published results, each term.',
            if (overview.passMark != null) 'Red: under the ${overview.passMark!.round()}% pass mark.',
            if (overview.weakBelow != null) 'Amber: under the ${overview.weakBelow!.round()}% weak line.',
          ].join(' '),
          style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _LinesCard extends StatelessWidget {
  const _LinesCard({
    required this.title,
    required this.overview,
    required this.lines,
    required this.firstColumn,
    this.detailColumn,
    this.showBelow = false,
  });

  final String title;
  final AcademicOverview overview;
  final List<AcademicLine> lines;
  final String firstColumn;

  /// A second label column - the subject, beside each class.
  final String? detailColumn;

  /// Whether to say how many students are under the weak line in the
  /// latest term.
  final bool showBelow;

  @override
  Widget build(BuildContext context) {
    final terms = overview.terms;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          HorizontalScrollTable(
            child: DataTable(
              columns: [
                DataColumn(label: Text(firstColumn)),
                if (detailColumn != null) DataColumn(label: Text(detailColumn!)),
                for (final term in terms)
                  DataColumn(label: Text(term.inProgress ? '${term.name} (so far)' : term.name), numeric: true),
                if (terms.length > 1) const DataColumn(label: Text('Change'), numeric: true),
                if (showBelow) const DataColumn(label: Text('Under the weak line'), numeric: true),
              ],
              rows: [
                for (final line in lines)
                  DataRow(
                    cells: [
                      DataCell(
                        line.detail == null || detailColumn != null
                            ? Text(line.label)
                            : Text.rich(
                                TextSpan(
                                  text: line.label,
                                  children: [
                                    TextSpan(
                                      text: '  ${line.detail}',
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                      if (detailColumn != null) DataCell(Text(line.detail ?? '-')),
                      for (final term in line.terms) DataCell(_Figure(figure: term, overview: overview)),
                      if (terms.length > 1) DataCell(_Change(line: line)),
                      if (showBelow) DataCell(Text(_belowLatest(line))),
                    ],
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Under the weak line in the latest term that has a figure.
  String _belowLatest(AcademicLine line) {
    final latest = line.terms.lastWhere((term) => term?.average != null, orElse: () => null);
    final below = latest?.studentsBelowTheMark;

    return below == null ? '-' : '$below of ${latest!.students ?? 0}';
  }
}

String _percent(double value) => value == value.roundToDouble() ? '${value.round()}%' : '${value.toStringAsFixed(1)}%';

class _Figure extends StatelessWidget {
  const _Figure({required this.figure, required this.overview});

  final TermFigure? figure;
  final AcademicOverview overview;

  @override
  Widget build(BuildContext context) {
    final average = figure?.average;
    if (average == null) return const Text('-');

    final colors = context.appColors;
    final (background, foreground) = overview.passMark != null && average < overview.passMark!
        ? (colors.dangerContainer, colors.onDangerContainer)
        : overview.weakBelow != null && average < overview.weakBelow!
        ? (colors.warningContainer, colors.onWarningContainer)
        : (null, null);

    final text = Text(
      _percent(average),
      style: TextStyle(fontWeight: FontWeight.w600, color: foreground),
    );
    if (background == null) return text;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: background, borderRadius: BorderRadius.circular(6)),
      child: text,
    );
  }
}

class _Change extends StatelessWidget {
  const _Change({required this.line});

  final AcademicLine line;

  @override
  Widget build(BuildContext context) {
    final change = line.lastChange;
    if (change == null) return const Text('-');

    final (latest, before) = change;
    final points = latest - before;
    final scheme = Theme.of(context).colorScheme;
    final size = points.abs();
    final text = size == size.roundToDouble() ? size.round().toString() : size.toStringAsFixed(1);

    if (points == 0) return const Text('0 pts');

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          points > 0 ? Icons.arrow_upward : Icons.arrow_downward,
          size: 14,
          color: points > 0 ? context.appColors.onSuccessContainer : scheme.error,
        ),
        const SizedBox(width: 2),
        Text('$text pts'),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  const _Notice(this.message);

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(child: Text(message, textAlign: TextAlign.center)),
      ),
    );
  }
}

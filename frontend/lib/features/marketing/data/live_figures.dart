/// Putting today's counts into the hero figures that asked for them -
/// the same rule the server follows (docs/marketing-content.md, slice 4).
///
/// The public page never runs this: it is handed figures the server has
/// already resolved, and is never told which of them are live. This copy
/// exists for the editor, which has to show the Super Admin what a live
/// figure would say before they publish it, and for the preview, which
/// draws boxes that have not been saved yet.
///
/// **A count of nothing falls back to the typed figure.** A front page
/// saying "0 Schools" helps nobody, and the typed value is already sitting
/// there saying something like "500+ (Target)".
library;

import 'package:intl/intl.dart';

/// The key of the hero's figures, and of the box naming where each one's
/// number comes from. They match `school/marketing.py`.
const heroStatsKey = 'hero.stats';
const statSourceKey = 'source';
const statValueKey = 'value';

/// The source meaning "whatever is typed in the box below".
const typedSource = 'typed';

final _grouped = NumberFormat.decimalPattern();

List<Map<String, String>> resolveLiveFigures(List<Map<String, String>> stats, Map<String, int> figures) {
  return [
    for (final stat in stats)
      if ((figures[stat[statSourceKey]] ?? 0) > 0)
        {...stat, statValueKey: _grouped.format(figures[stat[statSourceKey]])}
      else
        stat,
  ];
}

/// What one figure reads today, or null when it is typed rather than
/// counted - the editor says this under the picker so somebody can see the
/// real number before putting it on the front page.
String? liveReading(String? source, Map<String, int> figures) {
  if (source == null || source == typedSource) return null;

  final count = figures[source];

  if (count == null) return null;

  return count > 0 ? _grouped.format(count) : null;
}

import 'package:edutrack_app/features/marketing/data/live_figures.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, String> typed(String value, String label) => {'source': 'typed', 'value': value, 'label': label};

Map<String, String> live(String source, String fallback, String label) => {
  'source': source,
  'value': fallback,
  'label': label,
};

/// Putting today's counts into the hero figures (docs/marketing-content.md,
/// slice 4).
///
/// The public page never runs this - it is handed figures the server has
/// already resolved. This copy is for the editor's hint and the preview,
/// and it has to follow the same rule, so the rule is pinned on both sides.
void main() {
  group('resolving the figures', () {
    test('a typed figure is left alone', () {
      final stats = [typed('500+', 'Schools')];

      expect(resolveLiveFigures(stats, {'schools': 12}), stats);
    });

    test('a live figure is replaced by the count', () {
      final resolved = resolveLiveFigures([live('schools', '500+', 'Schools')], {'schools': 12});

      expect(resolved.single['value'], '12');
    });

    test('a big count is grouped so it can be read', () {
      final resolved = resolveLiveFigures([live('students', '1M+', 'Students')], {'students': 1248});

      expect(resolved.single['value'], '1,248');
    });

    test('a count of nothing falls back to what was typed', () {
      // A front page saying "0 Schools" helps nobody.
      final resolved = resolveLiveFigures([live('schools', '500+', 'Schools')], {'schools': 0});

      expect(resolved.single['value'], '500+');
    });

    test('a count nobody sent falls back too', () {
      // The editor has not loaded its figures yet, or the source is one
      // this build does not know about.
      final resolved = resolveLiveFigures([live('schools', '500+', 'Schools')], const {});

      expect(resolved.single['value'], '500+');
    });

    test('the label and the source are untouched', () {
      final resolved = resolveLiveFigures([live('schools', '500+', 'Schools')], {'schools': 12}).single;

      expect(resolved['label'], 'Schools');
      expect(resolved['source'], 'schools');
    });

    test('the figures that were not live keep their place in the row', () {
      final resolved = resolveLiveFigures(
        [typed('Global', 'Reach'), live('schools', '500+', 'Schools'), typed('Better', 'Tomorrow')],
        {'schools': 7},
      );

      expect(resolved.map((stat) => stat['value']).toList(), ['Global', '7', 'Better']);
    });

    test('an empty row resolves to an empty row', () {
      expect(resolveLiveFigures(const [], {'schools': 12}), isEmpty);
    });
  });

  group('what the editor says a figure reads today', () {
    test('a typed figure reads nothing, because it is not counted', () {
      expect(liveReading('typed', {'schools': 12}), isNull);
      expect(liveReading(null, {'schools': 12}), isNull);
    });

    test('a live figure reads its count, grouped', () {
      expect(liveReading('students', {'students': 1248}), '1,248');
    });

    test('a count of nothing reads nothing, so the editor can say why', () {
      expect(liveReading('schools', {'schools': 0}), isNull);
    });

    test('a source the figures say nothing about reads nothing', () {
      expect(liveReading('teachers', {'schools': 12}), isNull);
    });
  });
}

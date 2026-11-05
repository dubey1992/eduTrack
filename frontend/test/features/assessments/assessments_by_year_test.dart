import 'package:edutrack_app/features/academic_years/application/viewed_year.dart';
import 'package:edutrack_app/features/assessments/application/assessment_list_notifier.dart';
import 'package:edutrack_app/features/assessments/data/assessment_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_assessment_repository.dart';
import '../../support/viewed_year_overrides.dart';

/// Class Tests follow the top bar's year (decided 2026-11-05).
void main() {
  test('the list asks for the year in view, and a new year starts on page one with no section', () async {
    final fake = FakeAssessmentRepository();
    final container = ProviderContainer(
      overrides: [assessmentRepositoryProvider.overrideWithValue(fake), ...viewedYearIs(null)],
    );
    addTearDown(container.dispose);

    await container.read(assessmentListNotifierProvider.future);
    expect(fake.yearFilters, [null]);

    await container.read(viewedYearIdProvider.notifier).choose(1);
    await container.read(assessmentListNotifierProvider.future);

    expect(fake.yearFilters.last, 1);
    expect(fake.lastSectionFilter, isNull);
  });
}

import 'package:edutrack_app/features/syllabus/application/syllabus_checklist_notifier.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_checklist.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_progress_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_syllabus_progress_repository.dart';

const _checklist = SyllabusChecklist(
  subjectId: 1,
  subjectName: 'Mathematics',
  classSectionId: 10,
  totalTopics: 2,
  completedTopics: 1,
  progressPercent: 50,
  topics: [
    SyllabusChecklistItem(
      id: 1,
      title: 'Whole Numbers',
      sequenceNumber: 1,
      completed: true,
      completedByName: 'Priya Sharma',
      completedAt: '2026-09-01T10:00:00Z',
    ),
    SyllabusChecklistItem(
      id: 2,
      title: 'Fractions',
      sequenceNumber: 2,
      completed: false,
      completedByName: null,
      completedAt: null,
    ),
  ],
);

void main() {
  ProviderContainer makeContainer(FakeSyllabusProgressRepository fake) {
    return ProviderContainer(overrides: [syllabusProgressRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the checklist for a class section and subject', () async {
    final fake = FakeSyllabusProgressRepository(checklist: _checklist);
    final container = makeContainer(fake);
    addTearDown(container.dispose);

    const params = SyllabusChecklistParams(classSectionId: 10, subjectId: 1);
    final result = await container.read(syllabusChecklistProvider(params).future);

    expect(result.totalTopics, 2);
    expect(result.completedTopics, 1);
    expect(result.topics, hasLength(2));
  });

  test('toggle() marks a topic complete and updates the state', () async {
    final fake = FakeSyllabusProgressRepository(checklist: _checklist);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    const params = SyllabusChecklistParams(classSectionId: 10, subjectId: 1);
    await container.read(syllabusChecklistProvider(params).future);

    await container.read(syllabusChecklistProvider(params).notifier).toggle(2, true);

    final state = container.read(syllabusChecklistProvider(params)).value!;
    expect(state.completedTopics, 2);
    expect(state.topics.firstWhere((t) => t.id == 2).completed, isTrue);
  });

  test('toggle() marks a topic incomplete and updates the state', () async {
    final fake = FakeSyllabusProgressRepository(checklist: _checklist);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    const params = SyllabusChecklistParams(classSectionId: 10, subjectId: 1);
    await container.read(syllabusChecklistProvider(params).future);

    await container.read(syllabusChecklistProvider(params).notifier).toggle(1, false);

    final state = container.read(syllabusChecklistProvider(params)).value!;
    expect(state.completedTopics, 0);
    expect(state.topics.firstWhere((t) => t.id == 1).completed, isFalse);
  });
}

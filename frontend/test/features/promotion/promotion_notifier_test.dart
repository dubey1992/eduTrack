import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/promotion/application/promotion_notifier.dart';
import 'package:edutrack_app/features/promotion/data/models/promotion_preview.dart';
import 'package:edutrack_app/features/promotion/data/promotion_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_promotion_repository.dart';

/// The wizard's state (docs/promotion.md): what it asks for, what it
/// remembers, and what it drops on purpose.
ProviderContainer containerWith(FakePromotionRepository fake) {
  final container = ProviderContainer(overrides: [promotionRepositoryProvider.overrideWithValue(fake)]);
  addTearDown(container.dispose);

  return container;
}

void main() {
  group('choosing what to promote', () {
    test('a preview is not offered until both the class and the year are chosen', () {
      final container = containerWith(FakePromotionRepository());
      final notifier = container.read(promotionNotifierProvider.notifier);

      expect(container.read(promotionNotifierProvider).canPreview, isFalse);

      notifier.setSourceSection(10);
      expect(container.read(promotionNotifierProvider).canPreview, isFalse, reason: 'no year yet');

      notifier.setTargetYear(2);
      expect(container.read(promotionNotifierProvider).canPreview, isTrue);
    });

    test('the section and the year travel to the server as chosen', () async {
      final fake = FakePromotionRepository();
      final container = containerWith(fake);
      final notifier = container.read(promotionNotifierProvider.notifier);

      notifier.setSourceSection(10);
      notifier.setTargetYear(2);
      notifier.setTargetSection(20);
      await notifier.loadPreview();

      expect(fake.lastCall, {'class_section_id': 10, 'to_academic_year_id': 2, 'to_class_section_id': 20});
    });

    test('asking for nothing asks the server nothing', () async {
      final fake = FakePromotionRepository();
      final container = containerWith(fake);

      await container.read(promotionNotifierProvider.notifier).loadPreview();

      expect(fake.calls, 0);
    });

    test('changing the year drops the target section chosen inside the old one', () async {
      final fake = FakePromotionRepository();
      final container = containerWith(fake);
      final notifier = container.read(promotionNotifierProvider.notifier);

      notifier.setSourceSection(10);
      notifier.setTargetYear(2);
      notifier.setTargetSection(20);
      notifier.setTargetYear(3);
      await notifier.loadPreview();

      expect(fake.lastCall!['to_class_section_id'], isNull, reason: 'that section belonged to the year just dropped');
    });

    test('changing the class drops the roster, which described the old one', () async {
      final container = containerWith(FakePromotionRepository());
      final notifier = container.read(promotionNotifierProvider.notifier);

      notifier.setSourceSection(10);
      notifier.setTargetYear(2);
      await notifier.loadPreview();
      expect(container.read(promotionNotifierProvider).hasPreview, isTrue);

      notifier.setSourceSection(11);

      expect(container.read(promotionNotifierProvider).hasPreview, isFalse);
    });

    test('a refused preview is held as an error rather than an empty list', () async {
      final container = containerWith(FakePromotionRepository(failure: Failure.network()));
      final notifier = container.read(promotionNotifierProvider.notifier);

      notifier.setSourceSection(10);
      notifier.setTargetYear(2);
      await notifier.loadPreview();

      expect(container.read(promotionNotifierProvider).preview.hasError, isTrue);
      expect(container.read(promotionNotifierProvider).hasPreview, isFalse);
    });
  });

  group('deciding per student', () {
    Future<ProviderContainer> loaded(FakePromotionRepository fake) async {
      final container = containerWith(fake);
      final notifier = container.read(promotionNotifierProvider.notifier);
      notifier.setSourceSection(10);
      notifier.setTargetYear(2);
      await notifier.loadPreview();

      return container;
    }

    test('every row starts on the server default, and the counts agree', () async {
      final container = await loaded(FakePromotionRepository());
      final state = container.read(promotionNotifierProvider);

      expect(state.outcomeFor(state.preview.value!.students.first), PromotionOutcome.promote);
      expect(state.counts[PromotionOutcome.promote], 2);
      expect(state.counts[PromotionOutcome.retain], 0);
    });

    test('changing one student changes only that student', () async {
      final container = await loaded(FakePromotionRepository());
      container.read(promotionNotifierProvider.notifier).setOutcome(1, PromotionOutcome.retain);

      final state = container.read(promotionNotifierProvider);

      expect(state.outcomeFor(state.preview.value!.students[0]), PromotionOutcome.retain);
      expect(state.outcomeFor(state.preview.value!.students[1]), PromotionOutcome.promote);
      expect(state.counts[PromotionOutcome.retain], 1);
      expect(state.counts[PromotionOutcome.promote], 1);
    });

    test('a blocked student is counted as moving nowhere', () async {
      final container = await loaded(
        FakePromotionRepository(
          preview: fakePreview(
            students: [
              fakePromotionStudent(),
              fakePromotionStudent(studentId: 2, name: 'Bina Kapoor', isBlocked: true, blockedReason: 'Already there.'),
            ],
          ),
        ),
      );

      expect(container.read(promotionNotifierProvider).counts[PromotionOutcome.promote], 1);
    });

    test('a bulk action applies to the rows on screen and leaves a blocked one alone', () async {
      final container = await loaded(
        FakePromotionRepository(
          preview: fakePreview(
            students: [
              fakePromotionStudent(),
              fakePromotionStudent(studentId: 2, name: 'Bina Kapoor', isBlocked: true),
            ],
          ),
        ),
      );

      container.read(promotionNotifierProvider.notifier).setOutcomeForVisible(PromotionOutcome.graduate);
      final state = container.read(promotionNotifierProvider);

      expect(state.outcomeFor(state.preview.value!.students[0]), PromotionOutcome.graduate);
      expect(state.outcomes.containsKey(2), isFalse, reason: 'nothing can be asked for a blocked student');
    });

    test('a bulk action on a filtered list touches only what the filter shows', () async {
      final container = await loaded(FakePromotionRepository());
      final notifier = container.read(promotionNotifierProvider.notifier);

      notifier.setSearch('Bina');
      notifier.setOutcomeForVisible(PromotionOutcome.retain);
      final state = container.read(promotionNotifierProvider);

      expect(state.outcomeFor(state.preview.value!.students[1]), PromotionOutcome.retain);
      expect(state.outcomeFor(state.preview.value!.students[0]), PromotionOutcome.promote);
    });

    test('the counts describe the whole class even while a search hides half of it', () async {
      final container = await loaded(FakePromotionRepository());
      container.read(promotionNotifierProvider.notifier).setSearch('Bina');

      final state = container.read(promotionNotifierProvider);

      expect(state.visibleStudents.length, 1);
      expect(state.counts[PromotionOutcome.promote], 2, reason: 'a run applies to the class, not to the search');
    });

    test('the search matches an admission number as well as a name', () async {
      final container = await loaded(FakePromotionRepository());
      container.read(promotionNotifierProvider.notifier).setSearch('adm-2');

      expect(container.read(promotionNotifierProvider).visibleStudents.single.studentId, 2);
    });

    test('resetting puts every row back to what the server suggested', () async {
      final container = await loaded(FakePromotionRepository());
      final notifier = container.read(promotionNotifierProvider.notifier);

      notifier.setOutcomeForVisible(PromotionOutcome.graduate);
      notifier.resetOutcomes();
      final state = container.read(promotionNotifierProvider);

      expect(state.counts[PromotionOutcome.promote], 2);
    });

    test('going back to the choices keeps them and forgets the decisions', () async {
      final fake = FakePromotionRepository();
      final container = await loaded(fake);
      final notifier = container.read(promotionNotifierProvider.notifier);

      notifier.setOutcome(1, PromotionOutcome.retain);
      notifier.backToChoices();
      final state = container.read(promotionNotifierProvider);

      expect(state.hasPreview, isFalse);
      expect(state.outcomes, isEmpty);
      expect(state.classSectionId, 10, reason: 'the screen should not ask for the same class twice');
      expect(state.canPreview, isTrue);
    });
  });

  group('reading the answer', () {
    test('the outcome values are the ones the API will be given', () {
      expect(PromotionOutcome.promote.apiValue, 'promote');
      expect(PromotionOutcome.retain.apiValue, 'retain');
      expect(PromotionOutcome.graduate.apiValue, 'graduate');
      expect(PromotionOutcome.leave.apiValue, 'leave');
    });

    test('an outcome the app does not know reads as promote rather than throwing', () {
      expect(PromotionOutcome.fromApiValue('transferred-sideways'), PromotionOutcome.promote);
    });

    test('a preview parses, including the parts that can be missing', () {
      final parsed = PromotionPreview.fromJson({
        'from': {
          'academic_year_id': 1,
          'academic_year_name': '2026-27',
          'class_section_id': 10,
          'class_section_name': 'Grade 8 A',
          'school_class_id': 5,
          'school_class_name': 'Grade 8',
        },
        'to': {
          'academic_year_id': 2,
          'academic_year_name': '2027-28',
          'class_section_id': null,
          'class_section_name': null,
          'school_class_id': null,
          'school_class_name': null,
          'is_suggested': true,
        },
        'is_graduating': true,
        'can_run': true,
        'cannot_run_reason': null,
        'suggestions': {'available': false, 'term_name': null, 'pass_percentage': null},
        'students': [
          {
            'student_id': 7,
            'name': 'Chetan Rao',
            'admission_number': 'ADM-7',
            'roll_number': null,
            'status': 'active',
            'default_outcome': 'graduate',
            'is_blocked': false,
            'blocked_reason': null,
            'average_percentage': null,
            'attendance_percentage': 91.5,
            'suggested_outcome': null,
            'suggestion_reason': null,
          },
        ],
      });

      expect(parsed.isGraduating, isTrue);
      expect(parsed.to.classSectionName, isNull);
      expect(parsed.students.single.defaultOutcome, PromotionOutcome.graduate);
      expect(parsed.students.single.attendancePercentage, 91.5);
      expect(parsed.suggestions.available, isFalse);
    });
  });
}

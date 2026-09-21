import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/academic_years/application/academic_term_notifier.dart';
import 'package:edutrack_app/features/academic_years/data/academic_term_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_term.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_term_repository.dart';

ProviderContainer containerWith(FakeAcademicTermRepository fake) {
  final container = ProviderContainer(
    overrides: [academicTermRepositoryProvider.overrideWithValue(fake)],
    // Riverpod 3 retries a failed provider by default, which would turn an
    // error case into a hang.
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);

  return container;
}

Future<List<AcademicTerm>> load(ProviderContainer container, int yearId) async {
  final sub = container.listen(academicTermsProvider(yearId), (_, _) {});
  addTearDown(sub.close);

  return container.read(academicTermsProvider(yearId).future);
}

void main() {
  test('loads only the terms of the year it was opened for', () async {
    final fake = FakeAcademicTermRepository(
      terms: [
        fakeTerm(id: 1, academicYearId: 1, name: 'Term 1', sequenceNumber: 1),
        fakeTerm(id: 2, academicYearId: 2, name: 'Term 1', sequenceNumber: 1),
      ],
    );

    final terms = await load(containerWith(fake), 1);

    expect(terms.map((term) => term.id), [1]);
  });

  test('lists terms in curriculum order, not the order they were added', () async {
    final fake = FakeAcademicTermRepository(
      terms: [
        fakeTerm(id: 1, name: 'Term 2', sequenceNumber: 2),
        fakeTerm(id: 2, name: 'Term 1', sequenceNumber: 1),
      ],
    );

    final terms = await load(containerWith(fake), 1);

    expect(terms.map((term) => term.name), ['Term 1', 'Term 2']);
  });

  test('a year with no terms loads as an empty list, not an error', () async {
    final terms = await load(containerWith(FakeAcademicTermRepository()), 1);

    expect(terms, isEmpty);
  });

  test('adding a term refreshes the list', () async {
    final fake = FakeAcademicTermRepository();
    final container = containerWith(fake);
    await load(container, 1);

    await container
        .read(academicTermsProvider(1).notifier)
        .addTerm(name: 'Term 1', sequenceNumber: 1, startDate: DateTime(2026, 4, 1), endDate: DateTime(2026, 8, 31));

    expect(container.read(academicTermsProvider(1)).value!.map((term) => term.name), ['Term 1']);
    expect(fake.calls, ['listForYear', 'create', 'listForYear']);
  });

  test('editing a term keeps the fields that were not sent', () async {
    final fake = FakeAcademicTermRepository(terms: [fakeTerm(id: 7, name: 'Term 1')]);
    final container = containerWith(fake);
    final loaded = await load(container, 1);

    await container
        .read(academicTermsProvider(1).notifier)
        .editTerm(
          loaded.first,
          name: 'First Term',
          sequenceNumber: 1,
          startDate: DateTime(2026, 4, 1),
          endDate: DateTime(2026, 9, 30),
        );

    final updated = container.read(academicTermsProvider(1)).value!.single;
    expect(updated.name, 'First Term');
    expect(updated.endDate, DateTime(2026, 9, 30));
  });

  test('deleting a term drops it from the list', () async {
    final fake = FakeAcademicTermRepository(terms: [fakeTerm(id: 3)]);
    final container = containerWith(fake);
    final loaded = await load(container, 1);

    await container.read(academicTermsProvider(1).notifier).deleteTerm(loaded.single);

    expect(container.read(academicTermsProvider(1)).value, isEmpty);
  });

  test('a failure to load surfaces as an error state with the message', () async {
    final fake = FakeAcademicTermRepository(
      failWith: {'listForYear': const Failure(code: 'SERVER_ERROR', message: 'Terms are unavailable.')},
    );
    final container = containerWith(fake);
    final sub = container.listen(academicTermsProvider(1), (_, _) {});
    addTearDown(sub.close);

    await expectLater(container.read(academicTermsProvider(1).future), throwsA(isA<Failure>()));
    expect(container.read(academicTermsProvider(1)).error, isA<Failure>());
  });

  test('a failed add leaves the list as it was and rethrows for the dialog', () async {
    final fake = FakeAcademicTermRepository(
      terms: [fakeTerm(id: 1)],
      failWith: {'create': const Failure(code: 'VALIDATION_ERROR', message: 'The name has already been taken.')},
    );
    final container = containerWith(fake);
    await load(container, 1);

    await expectLater(
      container
          .read(academicTermsProvider(1).notifier)
          .addTerm(name: 'Term 1', sequenceNumber: 2, startDate: DateTime(2026, 9, 1), endDate: DateTime(2027, 3, 31)),
      throwsA(isA<Failure>()),
    );
    expect(container.read(academicTermsProvider(1)).value!.length, 1);
  });

  group('the order offered for the next term', () {
    test('starts at 1 in an empty year', () async {
      final container = containerWith(FakeAcademicTermRepository());
      await load(container, 1);

      expect(container.read(academicTermsProvider(1).notifier).nextSequenceNumber, 1);
    });

    test('is one past the highest in use, not the count', () async {
      final fake = FakeAcademicTermRepository(
        terms: [
          fakeTerm(id: 1, sequenceNumber: 1),
          fakeTerm(id: 2, name: 'Term 5', sequenceNumber: 5),
        ],
      );
      final container = containerWith(fake);
      await load(container, 1);

      expect(container.read(academicTermsProvider(1).notifier).nextSequenceNumber, 6);
    });
  });
}

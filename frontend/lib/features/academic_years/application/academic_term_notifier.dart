import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/academic_term_repository.dart';
import '../data/models/academic_term.dart';

/// The terms of one academic year, keyed by the year.
///
/// A family rather than a filter on one list: the dialog is opened per year,
/// and two years' terms are never shown together.
final academicTermsProvider = AsyncNotifierProvider.autoDispose.family<AcademicTermNotifier, List<AcademicTerm>, int>(
  AcademicTermNotifier.new,
);

class AcademicTermNotifier extends AsyncNotifier<List<AcademicTerm>> {
  // Riverpod 3 does not hand the key to build(), so it is a constructor field.
  AcademicTermNotifier(this.academicYearId);

  final int academicYearId;

  @override
  Future<List<AcademicTerm>> build() => _fetch();

  Future<List<AcademicTerm>> _fetch() {
    return ref.read(academicTermRepositoryProvider).listForYear(academicYearId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> addTerm({
    required String name,
    required int sequenceNumber,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await ref
        .read(academicTermRepositoryProvider)
        .create(
          academicYearId: academicYearId,
          name: name,
          sequenceNumber: sequenceNumber,
          startDate: startDate,
          endDate: endDate,
        );

    await refresh();
  }

  Future<void> editTerm(
    AcademicTerm term, {
    required String name,
    required int sequenceNumber,
    required DateTime startDate,
    required DateTime endDate,
  }) async {
    await ref
        .read(academicTermRepositoryProvider)
        .update(term.id, name: name, sequenceNumber: sequenceNumber, startDate: startDate, endDate: endDate);

    await refresh();
  }

  Future<void> deleteTerm(AcademicTerm term) async {
    await ref.read(academicTermRepositoryProvider).delete(term.id);
    await refresh();
  }

  /// The order to offer for the next term: one past the highest in use.
  int get nextSequenceNumber {
    final terms = state.value ?? const <AcademicTerm>[];
    if (terms.isEmpty) return 1;

    return terms.map((term) => term.sequenceNumber).reduce((a, b) => a > b ? a : b) + 1;
  }
}

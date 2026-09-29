import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/student_performance.dart';
import '../data/student_repository.dart';

/// One student's performance, keyed by the student (docs/assessments.md).
///
/// The chosen term lives here rather than in the widget: changing it is a
/// fetch, and a dialog that held the term itself would lose it the moment
/// the request failed and the screen rebuilt on the error.
final studentPerformanceProvider = AsyncNotifierProvider.autoDispose
    .family<StudentPerformanceNotifier, StudentPerformance, int>(StudentPerformanceNotifier.new);

class StudentPerformanceNotifier extends AsyncNotifier<StudentPerformance> {
  // Riverpod 3 does not hand the key to build(), so it is a constructor field.
  StudentPerformanceNotifier(this.studentId);

  final int studentId;

  /// Null means "whichever term the school is in", which is what the server
  /// picks when nobody says.
  int? _termId;

  int? get termId => _termId;

  @override
  Future<StudentPerformance> build() => _fetch();

  Future<StudentPerformance> _fetch() {
    return ref.read(studentRepositoryProvider).performance(studentId, academicTermId: _termId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }

  Future<void> setTerm(int? termId) async {
    if (termId == _termId) return;

    _termId = termId;
    await refresh();
  }
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/student_enrollment.dart';
import '../data/student_repository.dart';

/// One student's history, keyed by the student.
///
/// A family rather than a filter: the dialog is opened per student, and two
/// students' histories are never shown together.
final studentEnrollmentsProvider = AsyncNotifierProvider.autoDispose
    .family<StudentEnrollmentNotifier, List<StudentEnrollment>, int>(StudentEnrollmentNotifier.new);

class StudentEnrollmentNotifier extends AsyncNotifier<List<StudentEnrollment>> {
  // Riverpod 3 does not hand the key to build(), so it is a constructor field.
  StudentEnrollmentNotifier(this.studentId);

  final int studentId;

  @override
  Future<List<StudentEnrollment>> build() => _fetch();

  Future<List<StudentEnrollment>> _fetch() {
    return ref.read(studentRepositoryProvider).enrollments(studentId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(_fetch);
  }
}

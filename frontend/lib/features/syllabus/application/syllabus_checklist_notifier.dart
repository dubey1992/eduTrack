import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/syllabus_checklist.dart';
import '../data/syllabus_progress_repository.dart';

class SyllabusChecklistParams {
  const SyllabusChecklistParams({required this.classSectionId, required this.subjectId});

  final int classSectionId;
  final int subjectId;

  @override
  bool operator ==(Object other) =>
      other is SyllabusChecklistParams && other.classSectionId == classSectionId && other.subjectId == subjectId;

  @override
  int get hashCode => Object.hash(classSectionId, subjectId);
}

final syllabusChecklistProvider = AsyncNotifierProvider.autoDispose
    .family<SyllabusChecklistNotifier, SyllabusChecklist, SyllabusChecklistParams>(SyllabusChecklistNotifier.new);

class SyllabusChecklistNotifier extends AsyncNotifier<SyllabusChecklist> {
  SyllabusChecklistNotifier(this.params);

  final SyllabusChecklistParams params;

  @override
  Future<SyllabusChecklist> build() {
    return ref
        .read(syllabusProgressRepositoryProvider)
        .checklist(classSectionId: params.classSectionId, subjectId: params.subjectId);
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref
          .read(syllabusProgressRepositoryProvider)
          .checklist(classSectionId: params.classSectionId, subjectId: params.subjectId),
    );
  }

  Future<void> toggle(int syllabusTopicId, bool completed) async {
    final updated = await ref
        .read(syllabusProgressRepositoryProvider)
        .toggle(syllabusTopicId: syllabusTopicId, classSectionId: params.classSectionId, completed: completed);
    state = AsyncData(updated);
  }
}

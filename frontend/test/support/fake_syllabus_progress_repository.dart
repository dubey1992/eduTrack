import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_checklist.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_progress_repository.dart';

class FakeSyllabusProgressRepository implements SyllabusProgressRepository {
  FakeSyllabusProgressRepository({required SyllabusChecklist checklist, this.failChecklistWith, this.failToggleWith})
    // Private field, public parameter - see AuthenticatedUser.
    // ignore: prefer_initializing_formals
    : _checklist = checklist;

  SyllabusChecklist _checklist;
  Failure? failChecklistWith;
  Failure? failToggleWith;

  @override
  Future<SyllabusChecklist> checklist({required int classSectionId, required int subjectId}) async {
    if (failChecklistWith != null) throw failChecklistWith!;
    return _checklist;
  }

  @override
  Future<SyllabusChecklist> toggle({
    required int syllabusTopicId,
    required int classSectionId,
    required bool completed,
  }) async {
    if (failToggleWith != null) throw failToggleWith!;

    final updatedItems = [
      for (final item in _checklist.topics)
        if (item.id == syllabusTopicId)
          SyllabusChecklistItem(
            id: item.id,
            title: item.title,
            sequenceNumber: item.sequenceNumber,
            completed: completed,
            completedByName: completed ? 'Test Teacher' : null,
            completedAt: completed ? '2026-09-11T10:00:00Z' : null,
          )
        else
          item,
    ];
    final completedCount = updatedItems.where((t) => t.completed).length;

    _checklist = SyllabusChecklist(
      subjectId: _checklist.subjectId,
      subjectName: _checklist.subjectName,
      classSectionId: _checklist.classSectionId,
      totalTopics: _checklist.totalTopics,
      completedTopics: completedCount,
      progressPercent: _checklist.totalTopics == 0 ? 0 : (completedCount / _checklist.totalTopics * 100).round(),
      topics: updatedItems,
    );
    return _checklist;
  }
}

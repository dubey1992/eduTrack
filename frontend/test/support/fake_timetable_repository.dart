import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/timetable/data/models/day_of_week.dart';
import 'package:edutrack_app/features/timetable/data/models/timetable_entry.dart';
import 'package:edutrack_app/features/timetable/data/timetable_repository.dart';

class FakeTimetableRepository implements TimetableRepository {
  FakeTimetableRepository({this.entries = const [], this.failUpsertWith});

  List<TimetableEntry> entries;
  Failure? failUpsertWith;

  Map<String, dynamic>? lastUpsertPayload;
  int? lastDeletedId;

  @override
  Future<List<TimetableEntry>> grid({int? classSectionId, int? teacherId}) async {
    return entries.where((e) {
      if (classSectionId != null) return e.classSectionId == classSectionId;
      if (teacherId != null) return e.teacherId == teacherId;
      return true;
    }).toList();
  }

  @override
  Future<TimetableEntry> upsert({
    int? schoolId,
    required int classSectionId,
    required int periodId,
    required DayOfWeek dayOfWeek,
    required int subjectId,
    required int teacherId,
  }) async {
    if (failUpsertWith != null) throw failUpsertWith!;
    lastUpsertPayload = {
      'class_section_id': classSectionId,
      'period_id': periodId,
      'day_of_week': dayOfWeek.apiValue,
      'subject_id': subjectId,
      'teacher_id': teacherId,
    };
    final existingIndex = entries.indexWhere(
      (e) => e.classSectionId == classSectionId && e.periodId == periodId && e.dayOfWeek == dayOfWeek,
    );
    final created = TimetableEntry(
      id: existingIndex >= 0 ? entries[existingIndex].id : entries.length + 1,
      schoolId: schoolId ?? 1,
      classSectionId: classSectionId,
      classSectionName: 'Grade 8 A',
      periodId: periodId,
      periodNumber: 1,
      dayOfWeek: dayOfWeek,
      subjectId: subjectId,
      subjectName: 'Mathematics',
      teacherId: teacherId,
      teacherName: 'Priya Sharma',
    );
    entries = existingIndex >= 0 ? [for (final e in entries) e.id == created.id ? created : e] : [...entries, created];
    return created;
  }

  @override
  Future<void> delete(int entryId) async {
    lastDeletedId = entryId;
    entries = entries.where((e) => e.id != entryId).toList();
  }
}

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/timetable/data/break_repository.dart';
import 'package:edutrack_app/features/timetable/data/models/school_break.dart';

/// A school's breaks, held in memory.
class FakeBreakRepository implements BreakRepository {
  FakeBreakRepository({List<SchoolBreak>? breaks, this.failCreateWith}) : breaks = breaks ?? [];

  final List<SchoolBreak> breaks;
  Failure? failCreateWith;

  /// What each create or update asked for, so a test can see make_room.
  final List<Map<String, Object?>> calls = [];

  @override
  Future<List<SchoolBreak>> list({int? schoolId}) async => List.unmodifiable(breaks);

  @override
  Future<SchoolBreak> create({
    int? schoolId,
    required String name,
    required String dayShape,
    required String startTime,
    required String endTime,
    bool makeRoom = false,
  }) async {
    calls.add({
      'op': 'create',
      'name': name,
      'day_shape': dayShape,
      'start': startTime,
      'end': endTime,
      'make_room': makeRoom,
    });
    if (failCreateWith != null) throw failCreateWith!;

    final made = SchoolBreak(
      id: breaks.length + 1,
      schoolId: schoolId ?? 1,
      name: name,
      dayShape: dayShape,
      startTime: startTime,
      endTime: endTime,
    );
    breaks.add(made);
    return made;
  }

  @override
  Future<SchoolBreak> update(
    int breakId, {
    String? name,
    String? startTime,
    String? endTime,
    bool makeRoom = false,
  }) async {
    calls.add({'op': 'update', 'id': breakId, 'name': name, 'start': startTime, 'end': endTime, 'make_room': makeRoom});

    final index = breaks.indexWhere((found) => found.id == breakId);
    final was = breaks[index];
    final changed = SchoolBreak(
      id: was.id,
      schoolId: was.schoolId,
      name: name ?? was.name,
      dayShape: was.dayShape,
      startTime: startTime ?? was.startTime,
      endTime: endTime ?? was.endTime,
    );
    breaks[index] = changed;
    return changed;
  }

  @override
  Future<void> delete(int breakId) async {
    calls.add({'op': 'delete', 'id': breakId});
    breaks.removeWhere((found) => found.id == breakId);
  }
}

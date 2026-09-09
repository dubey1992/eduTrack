import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/timetable/data/models/period.dart';
import 'package:edutrack_app/features/timetable/data/period_repository.dart';

class FakePeriodRepository implements PeriodRepository {
  FakePeriodRepository({this.periods = const [], this.failWith});

  List<Period> periods;
  Failure? failWith;

  int? lastDeletedId;

  @override
  Future<List<Period>> list({int? schoolId}) async {
    if (failWith != null) throw failWith!;
    return periods;
  }

  @override
  Future<Period> create({
    int? schoolId,
    required int periodNumber,
    required String startTime,
    required String endTime,
  }) async {
    if (failWith != null) throw failWith!;
    final created = Period(
      id: periods.length + 1,
      schoolId: schoolId ?? 1,
      periodNumber: periodNumber,
      startTime: startTime,
      endTime: endTime,
    );
    periods = [...periods, created];
    return created;
  }

  @override
  Future<Period> update(int periodId, {int? periodNumber, String? startTime, String? endTime}) async {
    if (failWith != null) throw failWith!;
    final existing = periods.firstWhere((p) => p.id == periodId);
    final updated = Period(
      id: existing.id,
      schoolId: existing.schoolId,
      periodNumber: periodNumber ?? existing.periodNumber,
      startTime: startTime ?? existing.startTime,
      endTime: endTime ?? existing.endTime,
    );
    periods = [for (final p in periods) p.id == periodId ? updated : p];
    return updated;
  }

  @override
  Future<void> delete(int periodId) async {
    if (failWith != null) throw failWith!;
    lastDeletedId = periodId;
    periods = periods.where((p) => p.id != periodId).toList();
  }
}

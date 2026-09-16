import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_topic.dart';
import 'package:edutrack_app/features/syllabus/data/syllabus_topic_repository.dart';

class FakeSyllabusTopicRepository implements SyllabusTopicRepository {
  FakeSyllabusTopicRepository({
    List<SyllabusTopic> topics = const [],
    this.failCreateWith,
    this.failUpdateWith,
    this.failDeleteWith,
    // Private field, public parameter - see AuthenticatedUser.
    // ignore: prefer_initializing_formals
  }) : _topics = topics;

  List<SyllabusTopic> _topics;
  Failure? failCreateWith;
  Failure? failUpdateWith;
  Failure? failDeleteWith;

  Map<String, dynamic>? lastCreatePayload;
  int? lastDeletedId;

  @override
  Future<List<SyllabusTopic>> list({required int subjectId}) async {
    return _topics.where((t) => t.subjectId == subjectId).toList()
      ..sort((a, b) => a.sequenceNumber.compareTo(b.sequenceNumber));
  }

  @override
  Future<SyllabusTopic> create({
    int? schoolId,
    required int subjectId,
    required String title,
    required int sequenceNumber,
  }) async {
    if (failCreateWith != null) throw failCreateWith!;
    lastCreatePayload = {'subject_id': subjectId, 'title': title, 'sequence_number': sequenceNumber};

    final created = SyllabusTopic(
      id: _topics.length + 1,
      schoolId: schoolId ?? 1,
      subjectId: subjectId,
      subjectName: 'Mathematics',
      title: title,
      sequenceNumber: sequenceNumber,
    );
    _topics = [..._topics, created];
    return created;
  }

  @override
  Future<SyllabusTopic> update(int topicId, {String? title, int? sequenceNumber}) async {
    if (failUpdateWith != null) throw failUpdateWith!;

    final existing = _topics.firstWhere((t) => t.id == topicId);
    final updated = SyllabusTopic(
      id: existing.id,
      schoolId: existing.schoolId,
      subjectId: existing.subjectId,
      subjectName: existing.subjectName,
      title: title ?? existing.title,
      sequenceNumber: sequenceNumber ?? existing.sequenceNumber,
    );
    _topics = [for (final t in _topics) t.id == topicId ? updated : t];
    return updated;
  }

  @override
  Future<void> delete(int topicId) async {
    if (failDeleteWith != null) throw failDeleteWith!;
    lastDeletedId = topicId;
    _topics = _topics.where((t) => t.id != topicId).toList();
  }
}

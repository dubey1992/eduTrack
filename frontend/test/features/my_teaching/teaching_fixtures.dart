import 'package:edutrack_app/features/syllabus/data/models/my_syllabus_class.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_checklist.dart';
import 'package:edutrack_app/features/syllabus/data/models/syllabus_topic.dart';
import 'package:edutrack_app/features/teaching_reports/data/models/teaching_report.dart';

/// Meera Joshi's teaching: Mathematics in Grade 3 A on Monday 26 October.
TeachingReport report({
  int id = 1,
  String date = '2026-10-26',
  String topic = 'Fractions: adding unlike denominators',
  bool reviewed = false,
  String? homework,
  String? syllabusTopicName,
}) => TeachingReport(
  id: id,
  schoolId: 1,
  timetableEntryId: 11,
  classSectionName: 'Grade 3 A',
  periodNumber: 1,
  subjectName: 'Mathematics',
  teacherId: 7,
  teacherName: 'Meera Joshi',
  reportDate: date,
  topicTaught: topic,
  homework: homework,
  remarks: null,
  reviewedBy: reviewed ? 9 : null,
  reviewedByName: reviewed ? 'Rohit Verma' : null,
  reviewedAt: reviewed ? '2026-10-26T12:00:00Z' : null,
  syllabusTopicName: syllabusTopicName,
);

const mathsGrade3A = MySyllabusClass(
  classSectionId: 622,
  classSection: 'Grade 3 A',
  subjectId: 31,
  subjectName: 'Mathematics',
  totalTopics: 4,
  completedTopics: 1,
  progressPercent: 25,
);

const scienceGrade4A = MySyllabusClass(
  classSectionId: 623,
  classSection: 'Grade 4 A',
  subjectId: 32,
  subjectName: 'Science',
  totalTopics: 0,
  completedTopics: 0,
  progressPercent: 0,
);

const mathsTopics = [
  SyllabusTopic(id: 101, schoolId: 1, subjectId: 31, subjectName: 'Mathematics', title: 'Fractions', sequenceNumber: 1),
  SyllabusTopic(id: 102, schoolId: 1, subjectId: 31, subjectName: 'Mathematics', title: 'Decimals', sequenceNumber: 2),
];

SyllabusChecklist mathsChecklist({bool firstDone = true}) => SyllabusChecklist(
  subjectId: 31,
  subjectName: 'Mathematics',
  classSectionId: 622,
  totalTopics: 2,
  completedTopics: firstDone ? 1 : 0,
  progressPercent: firstDone ? 50 : 0,
  topics: [
    SyllabusChecklistItem(
      id: 101,
      title: 'Fractions',
      sequenceNumber: 1,
      completed: firstDone,
      completedByName: firstDone ? 'Meera Joshi' : null,
      completedAt: firstDone ? '2026-10-20T09:00:00Z' : null,
    ),
    const SyllabusChecklistItem(
      id: 102,
      title: 'Decimals',
      sequenceNumber: 2,
      completed: false,
      completedByName: null,
      completedAt: null,
    ),
  ],
);

extension NoTopics on SyllabusChecklist {
  SyllabusChecklist copyWithNoTopics() => SyllabusChecklist(
    subjectId: subjectId,
    subjectName: subjectName,
    classSectionId: classSectionId,
    totalTopics: 0,
    completedTopics: 0,
    progressPercent: 0,
    topics: const [],
  );
}

/// A class test: one subject, one section, one term (docs/assessments.md).
///
/// Marks are strings, the way money is: a client reading 17.50 as a double
/// would render 17.5 for a mark the teacher typed.
class Assessment {
  const Assessment({
    required this.id,
    required this.schoolId,
    required this.academicTermId,
    required this.termName,
    required this.classSectionId,
    required this.classSectionName,
    required this.subjectId,
    required this.subjectName,
    required this.syllabusTopicId,
    required this.syllabusTopicTitle,
    required this.gradeScaleId,
    required this.gradeScaleName,
    required this.type,
    required this.title,
    required this.maxMarks,
    required this.passMarks,
    required this.weightage,
    required this.assessmentDate,
    required this.status,
    required this.createdByName,
  });

  factory Assessment.fromJson(Map<String, dynamic> json) {
    return Assessment(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      academicTermId: json['academic_term_id'] as int,
      termName: json['term_name'] as String,
      classSectionId: json['class_section_id'] as int,
      classSectionName: json['class_section_name'] as String,
      subjectId: json['subject_id'] as int,
      subjectName: json['subject_name'] as String,
      syllabusTopicId: json['syllabus_topic_id'] as int?,
      syllabusTopicTitle: json['syllabus_topic_title'] as String?,
      gradeScaleId: json['grade_scale_id'] as int?,
      gradeScaleName: json['grade_scale_name'] as String?,
      type: AssessmentType.fromApiValue(json['type'] as String),
      title: json['title'] as String,
      maxMarks: json['max_marks'] as String,
      passMarks: json['pass_marks'] as String?,
      weightage: json['weightage'] as String?,
      assessmentDate: DateTime.parse(json['assessment_date'] as String),
      status: AssessmentStatus.fromApiValue(json['status'] as String),
      createdByName: json['created_by_name'] as String,
    );
  }

  final int id;
  final int schoolId;
  final int academicTermId;
  final String termName;
  final int classSectionId;
  final String classSectionName;
  final int subjectId;
  final String subjectName;
  final int? syllabusTopicId;
  final String? syllabusTopicTitle;
  final int? gradeScaleId;
  final String? gradeScaleName;
  final AssessmentType type;
  final String title;
  final String maxMarks;
  final String? passMarks;
  final String? weightage;
  final DateTime assessmentDate;
  final AssessmentStatus status;
  final String createdByName;

  bool get isDraft => status == AssessmentStatus.draft;

  /// "20", not "20.00": the second decimal is stored, rarely worth reading.
  String get maxMarksLabel => tidyMarks(maxMarks) ?? '';

  static String? tidyMarks(String? marks) {
    if (marks == null) return null;

    final parsed = double.tryParse(marks);
    if (parsed == null) return marks;
    if (parsed == parsed.roundToDouble()) return parsed.round().toString();

    return marks.replaceFirst(RegExp('0+\$'), '');
  }
}

enum AssessmentType {
  classTest('class_test', 'Class test'),
  unitTest('unit_test', 'Unit test'),
  assignment('assignment', 'Assignment'),
  quiz('quiz', 'Quiz'),
  practical('practical', 'Practical');

  const AssessmentType(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AssessmentType fromApiValue(String value) {
    return values.firstWhere((type) => type.apiValue == value, orElse: () => AssessmentType.classTest);
  }
}

enum AssessmentStatus {
  draft('draft', 'Draft'),
  published('published', 'Published');

  const AssessmentStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static AssessmentStatus fromApiValue(String value) {
    return values.firstWhere((status) => status.apiValue == value, orElse: () => AssessmentStatus.draft);
  }
}

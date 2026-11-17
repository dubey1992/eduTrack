/// An exam of one academic year and its date sheet (docs/examinations.md).
///
/// Dates arrive as `yyyy-mm-dd` and times as 24-hour `HH:MM` strings, in the
/// school's own wall-clock time - never instants, so nothing here converts
/// them to the device's timezone.
enum ExamCardStyle {
  classic('classic', 'Classic (light blue)'),
  mono('mono', 'Black & white');

  const ExamCardStyle(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static ExamCardStyle fromApiValue(String? value) =>
      ExamCardStyle.values.firstWhere((style) => style.apiValue == value, orElse: () => ExamCardStyle.classic);
}

class ExamPaper {
  const ExamPaper({
    this.id,
    required this.schoolClassId,
    this.schoolClassName,
    required this.subjectId,
    this.subjectName,
    required this.examDate,
    required this.startTime,
    required this.endTime,
  });

  factory ExamPaper.fromJson(Map<String, dynamic> json) => ExamPaper(
    id: json['id'] as int?,
    schoolClassId: json['school_class_id'] as int,
    schoolClassName: json['school_class_name'] as String?,
    subjectId: json['subject_id'] as int,
    subjectName: json['subject_name'] as String?,
    examDate: json['exam_date'] as String,
    startTime: json['start_time'] as String,
    endTime: json['end_time'] as String,
  );

  final int? id;
  final int schoolClassId;
  final String? schoolClassName;
  final int subjectId;
  final String? subjectName;
  final String examDate;
  final String startTime;
  final String endTime;

  Map<String, dynamic> toJson() => {
    'school_class_id': schoolClassId,
    'subject_id': subjectId,
    'exam_date': examDate,
    'start_time': startTime,
    'end_time': endTime,
  };
}

class ExamVersion {
  const ExamVersion({required this.version, required this.publishedOn});

  factory ExamVersion.fromJson(Map<String, dynamic> json) =>
      ExamVersion(version: json['version'] as int, publishedOn: json['published_on'] as String? ?? '');

  final int version;

  /// The school-local day it was published, already in the app's date order.
  final String publishedOn;
}

class Examination {
  const Examination({
    required this.id,
    required this.academicYearId,
    required this.academicYearName,
    this.academicTermId,
    this.academicTermName,
    required this.name,
    this.centre,
    this.reportingTime,
    this.instructions,
    this.cardStyle = ExamCardStyle.classic,
    this.blockOnFeeDues = false,
    required this.status,
    required this.version,
    this.hasUnpublishedChanges = false,
    this.paperCount = 0,
    this.classCount = 0,
    this.firstDate,
    this.lastDate,
    this.papers = const [],
    this.versions = const [],
  });

  factory Examination.fromJson(Map<String, dynamic> json) => Examination(
    id: json['id'] as int,
    academicYearId: json['academic_year_id'] as int,
    academicYearName: json['academic_year_name'] as String? ?? '',
    academicTermId: json['academic_term_id'] as int?,
    academicTermName: json['academic_term_name'] as String?,
    name: json['name'] as String,
    centre: json['centre'] as String?,
    reportingTime: json['reporting_time'] as String?,
    instructions: json['instructions'] as String?,
    cardStyle: ExamCardStyle.fromApiValue(json['card_style'] as String?),
    blockOnFeeDues: json['block_on_fee_dues'] as bool? ?? false,
    status: json['status'] as String? ?? 'draft',
    version: json['version'] as int? ?? 0,
    hasUnpublishedChanges: json['has_unpublished_changes'] as bool? ?? false,
    paperCount: json['paper_count'] as int? ?? 0,
    classCount: json['class_count'] as int? ?? 0,
    firstDate: json['first_date'] as String?,
    lastDate: json['last_date'] as String?,
    papers: [
      for (final row in (json['papers'] as List<dynamic>? ?? const [])) ExamPaper.fromJson(row as Map<String, dynamic>),
    ],
    versions: [
      for (final row in (json['versions'] as List<dynamic>? ?? const []))
        ExamVersion.fromJson(row as Map<String, dynamic>),
    ],
  );

  final int id;
  final int academicYearId;
  final String academicYearName;
  final int? academicTermId;
  final String? academicTermName;
  final String name;
  final String? centre;
  final String? reportingTime;
  final String? instructions;
  final ExamCardStyle cardStyle;
  final bool blockOnFeeDues;
  final String status;
  final int version;
  final bool hasUnpublishedChanges;
  final int paperCount;
  final int classCount;
  final String? firstDate;
  final String? lastDate;
  final List<ExamPaper> papers;

  /// Newest first. Empty for a draft that was never published.
  final List<ExamVersion> versions;

  bool get isPublished => version > 0;

  /// "Draft", "Published · v2", or "v2 · changes not published".
  String get statusLabel {
    if (!isPublished) return 'Draft';
    if (hasUnpublishedChanges) return 'Version $version · changes not published';
    return 'Published · version $version';
  }
}

/// The states a card can be in, as the server decides them.
enum CardState {
  ready('ready', 'Ready'),
  notPublished('not_published', 'Not published yet'),
  noPapers('no_papers', 'No papers for this class'),
  withheld('withheld', 'Withheld'),
  feeHold('fee_hold', 'Held: fees overdue');

  const CardState(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static CardState fromApiValue(String? value) =>
      CardState.values.firstWhere((state) => state.apiValue == value, orElse: () => CardState.notPublished);
}

class ExamCandidate {
  const ExamCandidate({
    required this.studentId,
    required this.name,
    required this.admissionNumber,
    required this.className,
    this.sectionId,
    this.sectionName,
    this.rollNumber,
    required this.state,
    this.reason,
    this.overdue,
    this.exception,
    this.missing = const [],
  });

  factory ExamCandidate.fromJson(Map<String, dynamic> json) => ExamCandidate(
    studentId: json['student_id'] as int,
    name: json['name'] as String,
    admissionNumber: json['admission_number'] as String? ?? '',
    className: json['school_class_name'] as String? ?? '',
    sectionId: json['class_section_id'] as int?,
    sectionName: json['class_section_name'] as String?,
    rollNumber: json['roll_number'] as String?,
    state: CardState.fromApiValue(json['state'] as String?),
    reason: json['reason'] as String?,
    overdue: json['overdue'] as String?,
    exception: json['exception'] as String?,
    missing: [for (final item in (json['missing'] as List<dynamic>? ?? const [])) item as String],
  );

  final int studentId;
  final String name;
  final String admissionNumber;
  final String className;
  final int? sectionId;
  final String? sectionName;
  final String? rollNumber;
  final CardState state;

  /// Staff only: why a card is withheld.
  final String? reason;

  /// Staff only: what is overdue, when fees hold the card.
  final String? overdue;

  /// "withhold", "allow" or null.
  final String? exception;

  /// Facts the card would print as a dash, such as "roll number".
  final List<String> missing;

  String get classLabel => [className, ?sectionName].join(' - ');
}

class CandidatePage {
  const CandidatePage({
    required this.items,
    required this.currentPage,
    required this.lastPage,
    required this.total,
    required this.counts,
  });

  final List<ExamCandidate> items;
  final int currentPage;
  final int lastPage;
  final int total;

  /// How many students are in each state, across the whole list.
  final Map<CardState, int> counts;
}

/// One printed batch: the PDF, and how many cards it holds and left out.
class CardBatch {
  const CardBatch({required this.bytes, required this.fileName, required this.printed, required this.skipped});

  final List<int> bytes;
  final String fileName;
  final int printed;
  final int skipped;
}

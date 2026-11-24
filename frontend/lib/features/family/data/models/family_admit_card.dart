/// One exam's admit card as a parent sees it (docs/examinations.md): whether
/// it can be downloaded, and the school's sentence when it cannot. The reason
/// a card is withheld is the school's to give, and never arrives here.
class FamilyAdmitCard {
  const FamilyAdmitCard({
    required this.examinationId,
    required this.name,
    required this.yearName,
    this.termName,
    required this.available,
    required this.state,
    required this.message,
    this.version,
    this.issuedOn,
    this.papers = const [],
    this.reportingTime,
    this.centre,
  });

  factory FamilyAdmitCard.fromJson(Map<String, dynamic> json) => FamilyAdmitCard(
    examinationId: json['examination_id'] as int,
    name: json['name'] as String,
    yearName: json['academic_year_name'] as String? ?? '',
    termName: json['term_name'] as String?,
    available: json['available'] as bool? ?? false,
    state: json['state'] as String? ?? '',
    message: json['message'] as String? ?? '',
    version: json['version'] as int?,
    issuedOn: json['issued_on'] as String?,
    papers: [
      for (final paper in (json['papers'] as List<dynamic>?) ?? const [])
        ExamPaper.fromJson(paper as Map<String, dynamic>),
    ],
    reportingTime: json['reporting_time'] as String?,
    centre: json['centre'] as String?,
  );

  final int examinationId;
  final String name;
  final String yearName;
  final String? termName;
  final bool available;
  final String state;
  final String message;
  final int? version;

  /// The day this version was published, in the app's date order.
  final String? issuedOn;

  /// The child's class's papers on the published date sheet - what "Add to
  /// calendar" puts in the phone (M8, 6.3). Empty from an older server.
  final List<ExamPaper> papers;

  /// `HH:mm`, when the school gives one.
  final String? reportingTime;
  final String? centre;
}

/// One paper of an exam's date sheet.
class ExamPaper {
  const ExamPaper({required this.subject, required this.date, required this.start, required this.end});

  factory ExamPaper.fromJson(Map<String, dynamic> json) => ExamPaper(
    subject: json['subject'] as String,
    date: DateTime.parse(json['date'] as String),
    start: json['start'] as String,
    end: json['end'] as String,
  );

  final String subject;
  final DateTime date;

  /// `HH:mm` on the school's clock.
  final String start;
  final String end;
}

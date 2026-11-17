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
}

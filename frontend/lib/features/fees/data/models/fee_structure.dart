/// How a fee is split over the year. Only fills the installments in - the
/// Accountant can change them afterwards (docs/fees.md).
enum FeeFrequency {
  monthly('monthly', 'Monthly'),
  quarterly('quarterly', 'Quarterly'),
  term('term', 'Per term'),
  yearly('yearly', 'Yearly'),
  oneTime('one_time', 'One-time');

  const FeeFrequency(this.wire, this.label);

  final String wire;
  final String label;

  /// Whether a day of the month means anything for it. A term's installments
  /// fall on the terms' own start dates, and a yearly or one-time fee on the
  /// first day of the year.
  bool get usesDueDay => this == monthly || this == quarterly;

  static FeeFrequency fromWire(String value) =>
      values.firstWhere((frequency) => frequency.wire == value, orElse: () => oneTime);
}

enum FeeStructureStatus {
  draft('draft', 'Draft'),
  published('published', 'Published');

  const FeeStructureStatus(this.wire, this.label);

  final String wire;
  final String label;

  static FeeStructureStatus fromWire(String value) =>
      values.firstWhere((status) => status.wire == value, orElse: () => draft);
}

/// One installment of a fee, as the server has it.
class FeeInstallment {
  const FeeInstallment({required this.sequence, required this.label, required this.dueDate, required this.amount});

  factory FeeInstallment.fromJson(Map<String, dynamic> json) {
    return FeeInstallment(
      sequence: json['sequence'] as int? ?? 0,
      label: json['label'] as String,
      dueDate: DateTime.parse(json['due_date'] as String),
      amount: json['amount'].toString(),
    );
  }

  final int sequence;
  final String label;

  /// A date in the school's calendar, not an instant - never converted.
  final DateTime dueDate;

  /// Exactly as the server wrote it ("1000.00"): money is not a double.
  final String amount;
}

/// What one class, or one bus route, is charged under one fee head for one
/// academic year.
class FeeStructure {
  const FeeStructure({
    required this.id,
    required this.schoolId,
    required this.academicYearId,
    required this.feeHeadId,
    required this.feeHeadName,
    required this.amount,
    required this.currencyCode,
    required this.frequency,
    required this.status,
    required this.installments,
    this.schoolClassId,
    this.schoolClassName,
    this.transportRouteId,
    this.transportRouteName,
    this.publishedAt,
    this.studentsCount = 0,
  });

  factory FeeStructure.fromJson(Map<String, dynamic> json) {
    final schoolClass = json['school_class'] as Map<String, dynamic>?;
    final route = json['transport_route'] as Map<String, dynamic>?;
    final head = json['fee_head'] as Map<String, dynamic>;

    return FeeStructure(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      academicYearId: json['academic_year_id'] as int,
      schoolClassId: schoolClass?['id'] as int?,
      schoolClassName: schoolClass?['name'] as String?,
      transportRouteId: route?['id'] as int?,
      transportRouteName: route?['name'] as String?,
      feeHeadId: head['id'] as int,
      feeHeadName: head['name'] as String,
      amount: json['amount'].toString(),
      currencyCode: json['currency_code'] as String,
      frequency: FeeFrequency.fromWire(json['frequency'] as String),
      status: FeeStructureStatus.fromWire(json['status'] as String),
      studentsCount: json['students_count'] as int? ?? 0,
      publishedAt: json['published_at'] is String ? DateTime.tryParse(json['published_at'] as String)?.toLocal() : null,
      installments: [
        for (final row in json['installments'] as List? ?? const [])
          FeeInstallment.fromJson(row as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final int schoolId;
  final int academicYearId;

  /// Set for a class fee; null for a bus route fee.
  final int? schoolClassId;
  final String? schoolClassName;

  /// Set for a bus route fee; null for a class fee.
  final int? transportRouteId;
  final String? transportRouteName;

  final int feeHeadId;
  final String feeHeadName;
  final String amount;
  final String currencyCode;
  final FeeFrequency frequency;
  final FeeStructureStatus status;
  final DateTime? publishedAt;
  final List<FeeInstallment> installments;

  /// How many students this fee charges now (F2). 0 for a draft.
  final int studentsCount;

  bool get isRouteFee => transportRouteId != null;
  bool get isDraft => status == FeeStructureStatus.draft;
}

/// An installment as the form holds it, before it is saved.
class InstallmentDraft {
  const InstallmentDraft({required this.label, required this.dueDate, required this.amount});

  factory InstallmentDraft.fromJson(Map<String, dynamic> json) => InstallmentDraft(
    label: json['label'] as String,
    dueDate: DateTime.parse(json['due_date'] as String),
    amount: json['amount'].toString(),
  );

  final String label;
  final DateTime dueDate;
  final String amount;
}

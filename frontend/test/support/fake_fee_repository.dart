import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/fees/data/fee_repository.dart';
import 'package:edutrack_app/features/fees/data/models/fee_head.dart';
import 'package:edutrack_app/features/fees/data/models/fee_structure.dart';
import 'package:edutrack_app/features/fees/data/money_text.dart';

/// Test double for [FeeRepository] - keeps heads and fees the way the server
/// would (Transport always first and protected, drafts and published), and
/// records what each call asked for.
class FakeFeeRepository implements FeeRepository {
  FakeFeeRepository({List<FeeHead>? heads, List<FeeStructure>? structures})
    : heads_ = heads ?? [transportHead, tuitionHead],
      structures_ = structures ?? [];

  static const transportHead = FeeHead(
    id: 1,
    schoolId: 1,
    name: 'Transport',
    isTransport: true,
    isActive: true,
    structuresCount: 0,
  );
  static const tuitionHead = FeeHead(
    id: 2,
    schoolId: 1,
    name: 'Tuition',
    isTransport: false,
    isActive: true,
    structuresCount: 0,
  );

  List<FeeHead> heads_;
  List<FeeStructure> structures_;

  /// Thrown by every read and write while set.
  Failure? failWith;

  /// Thrown by create/update of a structure only.
  Failure? failSaveWith;

  /// What [installmentPlan] answers.
  List<InstallmentDraft> plan = [
    InstallmentDraft(label: 'Term 1', dueDate: DateTime(2026, 4, 10), amount: '6000.00'),
    InstallmentDraft(label: 'Term 2', dueDate: DateTime(2026, 10, 10), amount: '6000.00'),
  ];

  final created = <Map<String, Object?>>[];
  final updated = <Map<String, Object?>>[];
  final published = <int>[];
  final deleted = <int>[];
  int publishAllCalls = 0;
  int planCalls = 0;

  void _check() {
    if (failWith != null) throw failWith!;
  }

  FeeHead _withCount(FeeHead head) => FeeHead(
    id: head.id,
    schoolId: head.schoolId,
    name: head.name,
    isTransport: head.isTransport,
    isActive: head.isActive,
    structuresCount: structures_.where((s) => s.feeHeadId == head.id).length,
  );

  @override
  Future<List<FeeHead>> heads({int? schoolId}) async {
    _check();
    return [for (final head in heads_) _withCount(head)];
  }

  @override
  Future<FeeHead> createHead({required String name, int? schoolId}) async {
    _check();
    if (heads_.any((head) => head.name.toLowerCase() == name.toLowerCase())) {
      throw const Failure(
        code: 'VALIDATION_ERROR',
        message: 'The given data was invalid.',
        details: {
          'errors': {
            'name': ['A fee type with this name already exists.'],
          },
        },
      );
    }
    final head = FeeHead(
      id: heads_.length + 1,
      schoolId: 1,
      name: name,
      isTransport: false,
      isActive: true,
      structuresCount: 0,
    );
    heads_.add(head);
    return head;
  }

  @override
  Future<FeeHead> updateHead(int id, {String? name, bool? isActive}) async {
    _check();
    final index = heads_.indexWhere((head) => head.id == id);
    final old = heads_[index];
    final head = FeeHead(
      id: id,
      schoolId: old.schoolId,
      name: name ?? old.name,
      isTransport: old.isTransport,
      isActive: isActive ?? old.isActive,
      structuresCount: 0,
    );
    heads_[index] = head;
    return _withCount(head);
  }

  @override
  Future<void> deleteHead(int id) async {
    _check();
    heads_.removeWhere((head) => head.id == id);
  }

  @override
  Future<List<FeeStructure>> structures({required int academicYearId, int? schoolId}) async {
    _check();
    return structures_.where((s) => s.academicYearId == academicYearId).toList();
  }

  FeeStructure _build({
    required int id,
    required int academicYearId,
    int? schoolClassId,
    int? transportRouteId,
    required int feeHeadId,
    required String amount,
    required FeeFrequency frequency,
    required List<InstallmentDraft> installments,
    FeeStructureStatus status = FeeStructureStatus.draft,
  }) {
    final head = heads_.firstWhere((head) => head.id == feeHeadId);
    return FeeStructure(
      id: id,
      schoolId: 1,
      academicYearId: academicYearId,
      schoolClassId: schoolClassId,
      schoolClassName: schoolClassId == null ? null : 'Class $schoolClassId',
      transportRouteId: transportRouteId,
      transportRouteName: transportRouteId == null ? null : 'Route $transportRouteId',
      feeHeadId: feeHeadId,
      feeHeadName: head.name,
      amount: amount,
      currencyCode: 'INR',
      frequency: frequency,
      status: status,
      installments: [
        for (var i = 0; i < installments.length; i++)
          FeeInstallment(
            sequence: i + 1,
            label: installments[i].label,
            dueDate: installments[i].dueDate,
            amount: installments[i].amount,
          ),
      ],
    );
  }

  @override
  Future<FeeStructure> createStructure({
    required int academicYearId,
    int? schoolClassId,
    int? transportRouteId,
    required int feeHeadId,
    required String amount,
    required FeeFrequency frequency,
    required List<InstallmentDraft> installments,
  }) async {
    _check();
    created.add({
      'academic_year_id': academicYearId,
      'school_class_id': schoolClassId,
      'transport_route_id': transportRouteId,
      'fee_head_id': feeHeadId,
      'amount': amount,
      'frequency': frequency.wire,
      'installments': installments.length,
      'installments_total': textOfCents(installments.fold(0, (sum, i) => sum + centsOf(i.amount)!)),
    });
    if (failSaveWith != null) throw failSaveWith!;

    final structure = _build(
      id: structures_.length + 100,
      academicYearId: academicYearId,
      schoolClassId: schoolClassId,
      transportRouteId: transportRouteId,
      feeHeadId: feeHeadId,
      amount: amount,
      frequency: frequency,
      installments: installments,
    );
    structures_.add(structure);
    return structure;
  }

  @override
  Future<FeeStructure> updateStructure(
    int id, {
    required String amount,
    required FeeFrequency frequency,
    required List<InstallmentDraft> installments,
  }) async {
    _check();
    updated.add({'id': id, 'amount': amount, 'frequency': frequency.wire, 'installments': installments.length});
    if (failSaveWith != null) throw failSaveWith!;

    final index = structures_.indexWhere((s) => s.id == id);
    final old = structures_[index];
    final structure = _build(
      id: id,
      academicYearId: old.academicYearId,
      schoolClassId: old.schoolClassId,
      transportRouteId: old.transportRouteId,
      feeHeadId: old.feeHeadId,
      amount: amount,
      frequency: frequency,
      installments: installments,
      status: old.status,
    );
    structures_[index] = structure;
    return structure;
  }

  @override
  Future<void> deleteStructure(int id) async {
    _check();
    deleted.add(id);
    structures_.removeWhere((s) => s.id == id);
  }

  FeeStructure _published(FeeStructure s) => _build(
    id: s.id,
    academicYearId: s.academicYearId,
    schoolClassId: s.schoolClassId,
    transportRouteId: s.transportRouteId,
    feeHeadId: s.feeHeadId,
    amount: s.amount,
    frequency: s.frequency,
    installments: [
      for (final i in s.installments) InstallmentDraft(label: i.label, dueDate: i.dueDate, amount: i.amount),
    ],
    status: FeeStructureStatus.published,
  );

  @override
  Future<FeeStructure> publishStructure(int id) async {
    _check();
    published.add(id);
    final index = structures_.indexWhere((s) => s.id == id);
    structures_[index] = _published(structures_[index]);
    return structures_[index];
  }

  @override
  Future<int> publishAll({required int academicYearId, int? schoolId}) async {
    _check();
    publishAllCalls++;
    var count = 0;
    for (var i = 0; i < structures_.length; i++) {
      if (structures_[i].academicYearId == academicYearId && structures_[i].isDraft) {
        structures_[i] = _published(structures_[i]);
        count++;
      }
    }
    return count;
  }

  @override
  Future<List<InstallmentDraft>> installmentPlan({
    required int academicYearId,
    required FeeFrequency frequency,
    required String amount,
    int dueDay = 10,
  }) async {
    _check();
    planCalls++;
    return plan;
  }
}

/// A class fee already in the fake: 12,000 a year for class [classId] in two
/// installments.
FeeStructure fakeClassFee({
  int id = 50,
  int classId = 1,
  int headId = 2,
  String headName = 'Tuition',
  FeeStructureStatus status = FeeStructureStatus.draft,
}) {
  return FeeStructure(
    id: id,
    schoolId: 1,
    academicYearId: 1,
    schoolClassId: classId,
    schoolClassName: 'Class 8',
    feeHeadId: headId,
    feeHeadName: headName,
    amount: '12000.00',
    currencyCode: 'INR',
    frequency: FeeFrequency.term,
    status: status,
    installments: [
      FeeInstallment(sequence: 1, label: 'Term 1', dueDate: DateTime(2026, 4, 10), amount: '6000.00'),
      FeeInstallment(sequence: 2, label: 'Term 2', dueDate: DateTime(2026, 10, 10), amount: '6000.00'),
    ],
  );
}

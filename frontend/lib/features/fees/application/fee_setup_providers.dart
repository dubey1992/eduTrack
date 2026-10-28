import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../classes/data/models/school_class.dart';
import '../../classes/data/school_class_repository.dart';
import '../../transport/data/models/transport_route.dart';
import '../../transport/data/transport_repository.dart';
import '../data/fee_repository.dart';
import '../data/models/fee_head.dart';
import '../data/models/fee_structure.dart';

/// Which school's fees, and which year's. [schoolId] is null for everybody
/// who does not choose a school - the server uses their own.
typedef FeeYearQuery = ({int? schoolId, int academicYearId});

// No automatic retry anywhere here: a refusal (module switched off, no
// access) is an answer, and the screens offer their own Try again.

final feeHeadsProvider = FutureProvider.autoDispose.family<List<FeeHead>, int?>(
  (ref, schoolId) => ref.read(feeRepositoryProvider).heads(schoolId: schoolId),
  retry: (retryCount, error) => null,
);

final feeStructuresProvider = FutureProvider.autoDispose.family<List<FeeStructure>, FeeYearQuery>(
  (ref, query) =>
      ref.read(feeRepositoryProvider).structures(academicYearId: query.academicYearId, schoolId: query.schoolId),
  retry: (retryCount, error) => null,
);

/// The classes a fee can be set for: that year's, since a class belongs to
/// one academic year.
final feeClassesProvider = FutureProvider.autoDispose.family<List<SchoolClass>, FeeYearQuery>(
  (ref, query) =>
      ref.read(schoolClassRepositoryProvider).list(schoolId: query.schoolId, academicYearId: query.academicYearId),
  retry: (retryCount, error) => null,
);

/// The routes a bus fee can be set for. Fails with MODULE_DISABLED for a
/// school with transport switched off, which the screen says plainly.
final feeRoutesProvider = FutureProvider.autoDispose.family<List<TransportRoute>, int?>(
  (ref, schoolId) => ref.read(transportRepositoryProvider).activeRoutes(schoolId: schoolId),
  retry: (retryCount, error) => null,
);

final feeSetupActionsProvider = Provider<FeeSetupActions>(FeeSetupActions.new);

/// Every change made on the Fee Setup screen, each followed by reading again
/// what it changed. Failures are thrown to the dialog or button that asked,
/// which says what went wrong.
class FeeSetupActions {
  FeeSetupActions(this._ref);

  final Ref _ref;

  FeeRepository get _repository => _ref.read(feeRepositoryProvider);

  /// Heads carry a count of the fees using them, and fees name their head,
  /// so a change to either reads both again.
  void _refresh() {
    _ref.invalidate(feeHeadsProvider);
    _ref.invalidate(feeStructuresProvider);
  }

  Future<FeeHead> createHead({required String name, int? schoolId}) async {
    final head = await _repository.createHead(name: name, schoolId: schoolId);
    _refresh();
    return head;
  }

  Future<FeeHead> renameHead(int id, String name) async {
    final head = await _repository.updateHead(id, name: name);
    _refresh();
    return head;
  }

  Future<FeeHead> setHeadActive(int id, {required bool active}) async {
    final head = await _repository.updateHead(id, isActive: active);
    _refresh();
    return head;
  }

  Future<void> deleteHead(int id) async {
    await _repository.deleteHead(id);
    _refresh();
  }

  Future<FeeStructure> createStructure({
    required int academicYearId,
    int? schoolClassId,
    int? transportRouteId,
    required int feeHeadId,
    required String amount,
    required FeeFrequency frequency,
    required List<InstallmentDraft> installments,
  }) async {
    final structure = await _repository.createStructure(
      academicYearId: academicYearId,
      schoolClassId: schoolClassId,
      transportRouteId: transportRouteId,
      feeHeadId: feeHeadId,
      amount: amount,
      frequency: frequency,
      installments: installments,
    );
    _refresh();
    return structure;
  }

  Future<FeeStructure> updateStructure(
    int id, {
    required String amount,
    required FeeFrequency frequency,
    required List<InstallmentDraft> installments,
  }) async {
    final structure = await _repository.updateStructure(
      id,
      amount: amount,
      frequency: frequency,
      installments: installments,
    );
    _refresh();
    return structure;
  }

  Future<void> deleteStructure(int id) async {
    await _repository.deleteStructure(id);
    _refresh();
  }

  Future<FeeStructure> publishStructure(int id) async {
    final structure = await _repository.publishStructure(id);
    _refresh();
    return structure;
  }

  Future<int> publishAll({required int academicYearId, int? schoolId}) async {
    final count = await _repository.publishAll(academicYearId: academicYearId, schoolId: schoolId);
    _refresh();
    return count;
  }

  Future<List<InstallmentDraft>> installmentPlan({
    required int academicYearId,
    required FeeFrequency frequency,
    required String amount,
    required int dueDay,
  }) {
    return _repository.installmentPlan(
      academicYearId: academicYearId,
      frequency: frequency,
      amount: amount,
      dueDay: dueDay,
    );
  }
}

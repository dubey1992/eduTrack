import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/paginated_response.dart';
import '../data/fee_repository.dart';
import '../data/models/student_fees.dart';

/// One page of the Student Fees list, as the filters stand.
typedef BalanceQuery = ({
  int? schoolId,
  int academicYearId,
  int? schoolClassId,
  String search,
  bool owingOnly,
  bool overdueOnly,
  int page,
  int perPage,
});

// No automatic retry: a refusal is an answer, and the screens offer their
// own Try again (the reason is in site_page_notifiers.dart).

final studentBalancesProvider = FutureProvider.autoDispose.family<PaginatedResponse<StudentBalance>, BalanceQuery>(
  (ref, query) => ref
      .read(feeRepositoryProvider)
      .balances(
        academicYearId: query.academicYearId,
        schoolId: query.schoolId,
        schoolClassId: query.schoolClassId,
        search: query.search,
        owingOnly: query.owingOnly,
        overdueOnly: query.overdueOnly,
        page: query.page,
        perPage: query.perPage,
      ),
  retry: (retryCount, error) => null,
);

/// One student's account. A null year is the server's choice: the current
/// one.
final studentStatementProvider = FutureProvider.autoDispose
    .family<StudentFeeStatement, ({int studentId, int? academicYearId})>(
      (ref, query) => ref.read(feeRepositoryProvider).statement(query.studentId, academicYearId: query.academicYearId),
      retry: (retryCount, error) => null,
    );

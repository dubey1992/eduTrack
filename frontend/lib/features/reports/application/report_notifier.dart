import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/report.dart';
import '../data/report_repository.dart';

/// What the reports screen is currently asking for.
///
/// Held as one value so a single provider covers every report: switching
/// report, moving the dates or asking for a comparison is a new query, not
/// new state to manage.
class ReportQuery {
  const ReportQuery({
    required this.kind,
    this.schoolId,
    this.from,
    this.to,
    this.classSectionId,
    this.departmentId,
    this.compare = false,
    this.below,
  });

  final ReportKind kind;
  final int? schoolId;
  final String? from;
  final String? to;
  final int? classSectionId;
  final int? departmentId;

  /// Whether to bring the same-length previous period alongside.
  final bool compare;

  /// Student attendance only: list just the students under this rate.
  final int? below;

  @override
  bool operator ==(Object other) {
    return other is ReportQuery &&
        other.kind == kind &&
        other.schoolId == schoolId &&
        other.from == from &&
        other.to == to &&
        other.classSectionId == classSectionId &&
        other.departmentId == departmentId &&
        other.compare == compare &&
        other.below == below;
  }

  @override
  int get hashCode => Object.hash(kind, schoolId, from, to, classSectionId, departmentId, compare, below);
}

/// The report for the current query.
///
/// No automatic retry: a report refused because the caller's role has no
/// access to it (403) is an answer, not a blip, and retrying would leave the
/// screen spinning on a question already settled.
final reportProvider = FutureProvider.autoDispose.family<ReportResult, ReportQuery>((ref, query) {
  return ref
      .watch(reportRepositoryProvider)
      .fetch(
        query.kind,
        schoolId: query.schoolId,
        from: query.from,
        to: query.to,
        classSectionId: query.classSectionId,
        departmentId: query.departmentId,
        compare: query.compare,
        below: query.below,
      );
}, retry: (retryCount, error) => null);

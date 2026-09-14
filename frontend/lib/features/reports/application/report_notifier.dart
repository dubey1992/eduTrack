import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/report.dart';
import '../data/report_repository.dart';

/// What the reports screen is currently asking for.
///
/// Held as one value so a single provider covers all four reports: switching
/// report or moving the dates is a new query, not new state to manage.
class ReportQuery {
  const ReportQuery({
    required this.kind,
    this.schoolId,
    this.from,
    this.to,
    this.classSectionId,
    this.departmentId,
  });

  final ReportKind kind;
  final int? schoolId;
  final String? from;
  final String? to;
  final int? classSectionId;
  final int? departmentId;

  ReportQuery copyWith({
    ReportKind? kind,
    int? schoolId,
    String? from,
    String? to,
    int? classSectionId,
    int? departmentId,
    bool clearSection = false,
  }) {
    return ReportQuery(
      kind: kind ?? this.kind,
      schoolId: schoolId ?? this.schoolId,
      from: from ?? this.from,
      to: to ?? this.to,
      classSectionId: clearSection ? null : (classSectionId ?? this.classSectionId),
      departmentId: departmentId ?? this.departmentId,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is ReportQuery &&
        other.kind == kind &&
        other.schoolId == schoolId &&
        other.from == from &&
        other.to == to &&
        other.classSectionId == classSectionId &&
        other.departmentId == departmentId;
  }

  @override
  int get hashCode => Object.hash(kind, schoolId, from, to, classSectionId, departmentId);
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
      );
}, retry: (retryCount, error) => null);

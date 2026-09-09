/// The KPI row the prototype's Daily Teaching Report screen shows for a
/// given date - how many periods were scheduled, how many already have a
/// report filed, and how many are still pending (see `GET
/// /teaching-reports/summary`).
class TeachingReportSummary {
  const TeachingReportSummary({required this.scheduled, required this.submitted, required this.pending});

  factory TeachingReportSummary.fromJson(Map<String, dynamic> json) {
    return TeachingReportSummary(
      scheduled: json['scheduled'] as int,
      submitted: json['submitted'] as int,
      pending: json['pending'] as int,
    );
  }

  final int scheduled;
  final int submitted;
  final int pending;
}

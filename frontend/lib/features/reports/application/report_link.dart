import 'package:intl/intl.dart';

import '../data/models/report.dart';

/// A report opened already set up - from a dashboard card, a quick action or
/// a person's line in "Collected today" (docs/dashboard.md).
///
/// It travels as the query string of /reports, so a link can be bookmarked
/// and the browser's back button lands on the same report. Anything the
/// screen cannot use is ignored rather than refused: a stale link opens the
/// reports screen as it always opened.
class ReportLink {
  const ReportLink({
    this.kind,
    this.schoolId,
    this.from,
    this.to,
    this.receivedBy,
    this.receivedByName,
    this.paymentMode,
  });

  factory ReportLink.fromQuery(Map<String, String> query) {
    final kind = ReportKind.values.where((kind) => kind.apiPath == query['report']).firstOrNull;
    final from = _date(query['from']);
    final to = _date(query['to']);
    final whole = from != null && to != null && !to.isBefore(from);

    return ReportLink(
      kind: kind,
      schoolId: int.tryParse(query['school_id'] ?? ''),
      // Both ends or neither: half a range is no range.
      from: whole ? from : null,
      to: whole ? to : null,
      receivedBy: int.tryParse(query['received_by'] ?? ''),
      receivedByName: query['received_by_name'],
      paymentMode: query['payment_mode'],
    );
  }

  final ReportKind? kind;

  /// The school or branch picked on the dashboard, for whoever picks one -
  /// so a branch's figure opens that branch's report, not the group's. The
  /// server still decides whether it is theirs to read.
  final int? schoolId;
  final DateTime? from;
  final DateTime? to;

  /// Fee collection only: one person's receipts, and their name to show on
  /// the filter before the report has loaded.
  final int? receivedBy;
  final String? receivedByName;
  final String? paymentMode;

  bool get isEmpty => kind == null && schoolId == null && from == null && receivedBy == null && paymentMode == null;

  String get location {
    final format = DateFormat('yyyy-MM-dd');

    return Uri(
      path: '/reports',
      queryParameters: {
        if (kind != null) 'report': kind!.apiPath,
        if (schoolId != null) 'school_id': '$schoolId',
        if (from != null) 'from': format.format(from!),
        if (to != null) 'to': format.format(to!),
        if (receivedBy != null) 'received_by': '$receivedBy',
        'received_by_name': ?receivedByName,
        'payment_mode': ?paymentMode,
      },
    ).toString();
  }

  static DateTime? _date(String? value) {
    if (value == null || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) return null;

    return DateTime.tryParse(value);
  }

  @override
  bool operator ==(Object other) => other is ReportLink && other.location == location;

  @override
  int get hashCode => location.hashCode;
}

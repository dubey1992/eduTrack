import 'package:flutter/material.dart';

import '../../../core/models/module_access.dart';
import '../../../core/routing/app_nav.dart';
import '../../auth/data/models/authenticated_user.dart';
import '../../reports/application/report_link.dart';
import '../../reports/data/models/report.dart';

/// Where a dashboard figure or quick action leads (docs/dashboard.md).
///
/// Every link is checked against the screen's own sidebar entry - the same
/// rule the router enforces - so the dashboard never offers a page that
/// would turn somebody away. The server still checks again when the page
/// loads; this only decides what is worth showing as clickable.
class DashboardLink {
  const DashboardLink(this.path, {this.report});

  /// A link into a fee report, opened already set to [report].
  DashboardLink.toReport(ReportLink this.report) : path = '/reports';

  final String path;
  final ReportLink? report;

  String get location => report?.location ?? path;

  bool allowedFor(AuthenticatedUser? user) {
    if (user == null) return false;

    final item = AppNav.findByPath(path);
    if (item == null || !item.allows(user)) return false;

    // A fee report also needs the fees module and the right to read fees,
    // the reports screen's own rule for showing them.
    return report?.kind?.isFees != true || user.canView(AppModules.fees);
  }
}

/// The page behind each card the server sends, by its key - or null for a
/// figure with nothing more to show.
///
/// [today] is the school's date the dashboard was read on, so "this month"
/// in a fee link is the school's month, not the browser's.
///
/// [schoolId] is the school picked in the dashboard's filter, if any: a
/// report opened from a branch's figure reports on that branch.
DashboardLink? linkForCard(String key, DateTime today, {int? schoolId}) {
  final monthStart = DateTime(today.year, today.month);

  return switch (key) {
    // The platform.
    'schools' || 'branches' => const DashboardLink('/schools'),
    'users' => const DashboardLink('/users'),
    'collected' || 'outstanding' => const DashboardLink('/payments'),
    // A school.
    'students' || 'boys' || 'girls' || 'gender_other' => const DashboardLink('/students'),
    'staff' || 'teachers' => const DashboardLink('/staff'),
    'attendance' || 'register' => const DashboardLink('/attendance'),
    'transport' || 'running' || 'completed' => const DashboardLink('/transport/trips'),
    'routes' => const DashboardLink('/transport/routes'),
    'performance' => const DashboardLink('/assessments'),
    'departments' => const DashboardLink('/departments'),
    'reviews' || 'reports' => const DashboardLink('/teaching-reports'),
    'periods' => const DashboardLink('/timetable'),
    'payroll' || 'salaries' || 'unpaid' => const DashboardLink('/payroll'),
    'leave' => const DashboardLink('/leaves'),
    'inbox' => const DashboardLink('/inbox'),
    // Fees: the reports behind the figures, over the card's own period.
    'fees_collected' => DashboardLink.toReport(
      ReportLink(kind: ReportKind.feeCollection, schoolId: schoolId, from: monthStart, to: today),
    ),
    'fees_outstanding' ||
    'fees_overdue' => DashboardLink.toReport(ReportLink(kind: ReportKind.feeOutstanding, schoolId: schoolId)),
    _ => null,
  };
}

/// One of the dashboard's quick actions.
class QuickAction {
  const QuickAction({
    required this.key,
    required this.label,
    required this.hint,
    required this.icon,
    required this.link,
  });

  final String key;
  final String label;
  final String hint;
  final IconData icon;
  final DashboardLink link;
}

/// The everyday jobs, each one click from the dashboard, in the order an
/// office reaches for them. Only those [user] may open are returned.
///
/// No date lock: the app has none yet, and a button for one would promise a
/// control that does not exist (docs/dashboard.md, "Open decisions").
List<QuickAction> quickActionsFor(AuthenticatedUser? user, DateTime today, {int? schoolId}) {
  final todaysCollection = ReportLink(kind: ReportKind.feeCollection, schoolId: schoolId, from: today, to: today);

  final actions = [
    const QuickAction(
      key: 'collect',
      label: 'Collect fees',
      hint: "Record a student's payment",
      icon: Icons.payments_outlined,
      link: DashboardLink('/student-fees'),
    ),
    QuickAction(
      key: 'collection-report',
      label: 'Collection report',
      hint: 'Today, by person and payment mode',
      icon: Icons.receipt_long_outlined,
      link: DashboardLink.toReport(todaysCollection),
    ),
    const QuickAction(
      key: 'receipts',
      label: 'Receipts',
      hint: 'Reprint, email or cancel one',
      icon: Icons.description_outlined,
      link: DashboardLink('/fee-receipts'),
    ),
    const QuickAction(
      key: 'students',
      label: 'Find a student',
      hint: 'Search by name or admission no.',
      icon: Icons.person_search_outlined,
      link: DashboardLink('/students'),
    ),
    const QuickAction(
      key: 'messages',
      label: 'Messages',
      hint: 'SMS and WhatsApp log',
      icon: Icons.forum_outlined,
      link: DashboardLink('/communication'),
    ),
    QuickAction(
      key: 'outstanding',
      label: 'Fees owed',
      hint: 'Who still owes, and how long',
      icon: Icons.account_balance_wallet_outlined,
      link: DashboardLink.toReport(ReportLink(kind: ReportKind.feeOutstanding, schoolId: schoolId)),
    ),
  ];

  return [
    for (final action in actions)
      if (action.link.allowedFor(user)) action,
  ];
}

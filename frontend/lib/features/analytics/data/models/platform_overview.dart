/// Platform analytics, A7 (docs/analytics.md), as `GET /analytics/platform`
/// sends it: the whole of School365ai, for the Super Admin. Every figure is
/// live and trial schools only (docs/school-categories.md).
library;

import '../../../schools/data/models/school.dart' show SchoolCategory;

class PlatformTotals {
  const PlatformTotals({
    required this.schoolsActive,
    required this.schoolsInactive,
    this.schoolsNotCounted = 0,
    required this.students,
    required this.staff,
    required this.users,
  });

  factory PlatformTotals.fromJson(Map<String, dynamic> json) {
    return PlatformTotals(
      schoolsActive: json['schools_active'] as int,
      schoolsInactive: json['schools_inactive'] as int,
      schoolsNotCounted: json['schools_not_counted'] as int? ?? 0,
      students: json['students'] as int,
      staff: json['staff'] as int,
      users: json['users'] as int,
    );
  }

  final int schoolsActive;
  final int schoolsInactive;

  /// Demo and testing schools: left out of every other figure here.
  final int schoolsNotCounted;
  final int students;
  final int staff;
  final int users;
}

/// One currency's payments in a month - never added to another's.
class PlatformPayment {
  const PlatformPayment({required this.currencyCode, required this.amount});

  factory PlatformPayment.fromJson(Map<String, dynamic> json) {
    return PlatformPayment(currencyCode: json['currency_code'] as String, amount: json['amount'] as String);
  }

  final String currencyCode;

  /// Exact, as the server sent it.
  final String amount;
}

class PlatformMonth {
  const PlatformMonth({
    required this.from,
    required this.newSchools,
    required this.signIns,
    required this.activeUsers,
    required this.messages,
    required this.payments,
    required this.earlyAccessRequests,
    required this.demoRequests,
  });

  factory PlatformMonth.fromJson(Map<String, dynamic> json) {
    final messages = json['messages'] as Map<String, dynamic>;

    return PlatformMonth(
      from: json['from'] as String,
      newSchools: json['new_schools'] as int,
      signIns: json['sign_ins'] as int,
      activeUsers: json['active_users'] as int,
      messages: {
        for (final entry in messages.entries)
          entry.key: (
            sent: (entry.value as Map<String, dynamic>)['sent'] as int,
            failed: (entry.value as Map<String, dynamic>)['failed'] as int,
          ),
      },
      payments: (json['payments'] as List<dynamic>)
          .map((row) => PlatformPayment.fromJson(row as Map<String, dynamic>))
          .toList(),
      earlyAccessRequests: json['early_access_requests'] as int,
      demoRequests: json['demo_requests'] as int,
    );
  }

  final String from;
  final int newSchools;
  final int signIns;

  /// Distinct people who signed in.
  final int activeUsers;

  /// Per outgoing channel ("sms", "whatsapp", "email"): sent and failed.
  final Map<String, ({int sent, int failed})> messages;
  final List<PlatformPayment> payments;
  final int earlyAccessRequests;
  final int demoRequests;
}

class PlatformSchool {
  const PlatformSchool({
    required this.name,
    required this.city,
    required this.status,
    this.category = SchoolCategory.live,
    this.trialEndsLabel,
    this.trialDaysLeft,
    required this.students,
    required this.staff,
    required this.lastSignInLabel,
    required this.recentSignIns,
    required this.recentMessages,
  });

  factory PlatformSchool.fromJson(Map<String, dynamic> json) {
    return PlatformSchool(
      name: json['name'] as String,
      city: json['city'] as String?,
      status: json['status'] as String,
      category: SchoolCategory.fromApiValue(json['category'] as String?),
      trialEndsLabel: json['trial_ends_label'] as String?,
      trialDaysLeft: json['trial_days_left'] as int?,
      students: json['students'] as int,
      staff: json['staff'] as int,
      lastSignInLabel: json['last_sign_in_label'] as String?,
      recentSignIns: json['recent_sign_ins'] as int,
      recentMessages: json['recent_messages'] as int,
    );
  }

  final String name;
  final String? city;
  final String status;
  final SchoolCategory category;
  final String? trialEndsLabel;
  final int? trialDaysLeft;
  final int students;
  final int staff;

  /// "In Trial - ends in 5 days", "In Trial - ended 09/01/2026", or the
  /// category alone.
  String get categoryText {
    final days = trialDaysLeft;
    if (category != SchoolCategory.trial || days == null) return category.label;
    if (days < 0) return 'In Trial - ended $trialEndsLabel';
    if (days == 0) return 'In Trial - ends today';

    return 'In Trial - ends in $days day${days == 1 ? '' : 's'}';
  }

  /// When anyone at the school last signed in; null if nobody ever has.
  final String? lastSignInLabel;
  final int recentSignIns;
  final int recentMessages;

  bool get isActive => status == 'active';
}

class PlatformModule {
  const PlatformModule({required this.label, required this.schoolsOn, required this.schools});

  factory PlatformModule.fromJson(Map<String, dynamic> json) {
    return PlatformModule(
      label: json['label'] as String,
      schoolsOn: json['schools_on'] as int,
      schools: json['schools'] as int,
    );
  }

  final String label;
  final int schoolsOn;
  final int schools;
}

class PlatformOverview {
  const PlatformOverview({required this.totals, required this.months, required this.modules, required this.recentDays});

  factory PlatformOverview.fromJson(Map<String, dynamic> json) {
    return PlatformOverview(
      totals: PlatformTotals.fromJson(json['totals'] as Map<String, dynamic>),
      months: (json['months'] as List<dynamic>)
          .map((row) => PlatformMonth.fromJson(row as Map<String, dynamic>))
          .toList(),
      modules: (json['modules'] as List<dynamic>)
          .map((row) => PlatformModule.fromJson(row as Map<String, dynamic>))
          .toList(),
      recentDays: json['recent_days'] as int? ?? 30,
    );
  }

  final PlatformTotals totals;
  final List<PlatformMonth> months;
  final List<PlatformModule> modules;

  /// "Recent" in the per-school table: the last this many days.
  final int recentDays;
}

import 'working_week.dart';

enum SchoolStatus {
  active('active'),
  inactive('inactive');

  const SchoolStatus(this.apiValue);

  final String apiValue;

  static SchoolStatus fromApiValue(String value) => SchoolStatus.values.firstWhere((s) => s.apiValue == value);
}

/// What kind of account a school is (docs/school-categories.md). Beside its
/// status, never instead of it.
enum SchoolCategory {
  live('live', 'Live'),
  trial('trial', 'In Trial'),
  demo('demo', 'Demo'),
  testing('testing', 'Testing');

  const SchoolCategory(this.apiValue, this.label);

  final String apiValue;
  final String label;

  /// Live and trial schools are customers; the platform's figures are theirs.
  bool get isCounted => this == live || this == trial;

  static SchoolCategory fromApiValue(String? value) =>
      SchoolCategory.values.firstWhere((c) => c.apiValue == value, orElse: () => SchoolCategory.live);
}

class School {
  const School({
    required this.id,
    required this.name,
    this.parentSchoolId,
    this.parentSchoolName,
    this.branchCount = 0,
    required this.registrationNumber,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.state,
    required this.country,
    required this.postalCode,
    this.latitude,
    this.longitude,
    required this.currencyCode,
    required this.timezone,
    this.workingDays = const WorkingWeek.mondayToFriday(),
    required this.logoUrl,
    required this.status,
    this.category = SchoolCategory.live,
    this.trialEndsOn,
    this.trialEndsLabel,
    this.trialDaysLeft,
  });

  factory School.fromJson(Map<String, dynamic> json) {
    return School(
      id: json['id'] as int,
      name: json['name'] as String,
      parentSchoolId: json['parent_school_id'] as int?,
      parentSchoolName: json['parent_school_name'] as String?,
      branchCount: json['branch_count'] as int? ?? 0,
      registrationNumber: json['registration_number'] as String?,
      email: json['email'] as String,
      phone: json['phone'] as String,
      address: json['address'] as String,
      city: json['city'] as String,
      state: json['state'] as String,
      country: json['country'] as String,
      postalCode: json['postal_code'] as String,
      latitude: json['latitude'] as String?,
      longitude: json['longitude'] as String?,
      currencyCode: json['currency_code'] as String,
      timezone: json['timezone'] as String? ?? 'UTC',
      workingDays: WorkingWeek.fromApiValue(json['working_days']),
      logoUrl: json['logo_url'] as String?,
      status: SchoolStatus.fromApiValue(json['status'] as String),
      category: SchoolCategory.fromApiValue(json['category'] as String?),
      trialEndsOn: json['trial_ends_on'] as String?,
      trialEndsLabel: json['trial_ends_label'] as String?,
      trialDaysLeft: json['trial_days_left'] as int?,
    );
  }

  final int id;
  final String name;

  /// The school this one is a branch of, if any. See docs/branches.md.
  final int? parentSchoolId;
  final String? parentSchoolName;

  /// How many branches sit beneath this one. Zero for a branch, and for a
  /// standalone school.
  final int branchCount;

  bool get isBranch => parentSchoolId != null;

  bool get isGroupParent => branchCount > 0;
  final String? registrationNumber;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String state;
  final String country;
  final String postalCode;

  /// Where the school is, if anyone has said. Kept as the string the
  /// API sent so a coordinate is never quietly rounded by a double on
  /// its way through the client.
  final String? latitude;
  final String? longitude;
  final String currencyCode;

  /// The IANA zone this school's dates and times are read in, e.g.
  /// `Asia/Kolkata`. Decides what "today" means for everything it records.
  final String timezone;

  /// The days this school runs. Monday to Friday unless somebody has
  /// said otherwise - which is what the product assumed everywhere
  /// until schools outside that week arrived.
  final WorkingWeek workingDays;
  final String? logoUrl;
  final SchoolStatus status;
  final SchoolCategory category;

  /// The day a trial ends, as the API sent it (yyyy-mm-dd); null for
  /// anything but a trial.
  final String? trialEndsOn;
  final String? trialEndsLabel;

  /// Negative once the trial has ended. The school keeps working.
  final int? trialDaysLeft;

  /// "Trial ends in 5 days", "Trial ends today", "Trial ended 09/01/2026" -
  /// or null for a school that is not in trial.
  String? get trialNote {
    final days = trialDaysLeft;
    if (category != SchoolCategory.trial || days == null) return null;
    if (days < 0) return 'Trial ended $trialEndsLabel';
    if (days == 0) return 'Trial ends today';

    return 'Trial ends in $days day${days == 1 ? '' : 's'}';
  }

  School copyWith({SchoolStatus? status}) {
    return School(
      id: id,
      name: name,
      registrationNumber: registrationNumber,
      email: email,
      phone: phone,
      address: address,
      city: city,
      state: state,
      country: country,
      postalCode: postalCode,
      latitude: latitude,
      longitude: longitude,
      currencyCode: currencyCode,
      timezone: timezone,
      workingDays: workingDays,
      logoUrl: logoUrl,
      status: status ?? this.status,
      category: category,
      trialEndsOn: trialEndsOn,
      trialEndsLabel: trialEndsLabel,
      trialDaysLeft: trialDaysLeft,
    );
  }
}

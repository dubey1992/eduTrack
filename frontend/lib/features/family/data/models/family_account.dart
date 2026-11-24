/// Who is signed in to the Family app, and the children they see
/// (`GET /family/me`, docs/parent-student-app.md).
class FamilyAccount {
  const FamilyAccount({
    required this.id,
    required this.name,
    required this.mobile,
    required this.schoolName,
    required this.currencyCode,
    required this.children,
    this.schoolPhone,
    this.schoolEmail,
    this.schoolAddress,
    this.features = FamilyFeatures.all,
  });

  factory FamilyAccount.fromJson(Map<String, dynamic> json) {
    final school = json['school'] as Map<String, dynamic>?;

    return FamilyAccount(
      id: json['id'] as int,
      name: json['name'] as String? ?? '',
      mobile: json['mobile'] as String?,
      schoolName: school?['name'] as String? ?? '',
      currencyCode: school?['currency_code'] as String? ?? 'INR',
      schoolPhone: school?['phone'] as String?,
      schoolEmail: school?['email'] as String?,
      schoolAddress: school?['address'] as String?,
      features: FamilyFeatures.fromJson(json['features'] as Map<String, dynamic>?),
      children: [
        for (final child in json['children'] as List<dynamic>? ?? const [])
          FamilyChild.fromJson(child as Map<String, dynamic>),
      ],
    );
  }

  final int id;
  final String name;
  final String? mobile;
  final String schoolName;
  final String currencyCode;
  final List<FamilyChild> children;

  /// The school office's own contact details, for "Contact the school".
  final String? schoolPhone;
  final String? schoolEmail;
  final String? schoolAddress;

  /// Which parts of the app the school uses.
  final FamilyFeatures features;

  /// Whether any child takes the school bus - the Bus tab is for them.
  bool get anyChildOnTransport => children.any((child) => child.hasTransport);

  /// The first word of the name, for "Good morning, Meera".
  String get firstName => name.trim().split(RegExp(r'\s+')).first;
}

/// One child, as their parent sees them.
class FamilyChild {
  const FamilyChild({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.className,
    required this.rollNumber,
    this.hasTransport = false,
  });

  factory FamilyChild.fromJson(Map<String, dynamic> json) {
    return FamilyChild(
      id: json['id'] as int,
      firstName: json['first_name'] as String? ?? '',
      lastName: json['last_name'] as String? ?? '',
      className: json['class_name'] as String?,
      rollNumber: json['roll_number']?.toString(),
      hasTransport: json['has_transport'] as bool? ?? false,
    );
  }

  final int id;
  final String firstName;
  final String lastName;
  final String? className;
  final String? rollNumber;

  /// Whether the school carries this child on a bus route.
  final bool hasTransport;

  String get fullName => '$firstName $lastName'.trim();

  String get initial => firstName.isEmpty ? '?' : String.fromCharCode(firstName.runes.first).toUpperCase();
}

/// Which parts of the app the school uses (`features` on `/family/me`). An
/// older server that does not say is taken to use them all.
class FamilyFeatures {
  const FamilyFeatures({
    required this.fees,
    required this.transport,
    required this.results,
    required this.timetable,
    required this.syllabus,
    this.homework = true,
  });

  factory FamilyFeatures.fromJson(Map<String, dynamic>? json) {
    if (json == null || json.isEmpty) return all;

    bool on(String key) => json[key] as bool? ?? true;
    return FamilyFeatures(
      fees: on('fees'),
      transport: on('transport'),
      results: on('results'),
      timetable: on('timetable'),
      syllabus: on('syllabus'),
      homework: on('homework'),
    );
  }

  static const all = FamilyFeatures(fees: true, transport: true, results: true, timetable: true, syllabus: true);

  final bool fees;
  final bool transport;
  final bool results;
  final bool timetable;
  final bool syllabus;

  /// From the teachers' teaching reports (M8, 8.1).
  final bool homework;
}

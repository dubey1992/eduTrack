/// One step of a new school's setup guide (docs/onboarding.md, O4). Done
/// when the school has the thing, never because somebody ticked it.
class SetupStep {
  const SetupStep({
    required this.key,
    required this.title,
    required this.detail,
    required this.path,
    required this.done,
    this.summary,
    this.blockedBy,
  });

  factory SetupStep.fromJson(Map<String, dynamic> json) => SetupStep(
    key: json['key'] as String,
    title: json['title'] as String,
    detail: json['detail'] as String,
    path: json['path'] as String,
    done: json['done'] as bool,
    summary: json['summary'] as String?,
    blockedBy: json['blocked_by'] as String?,
  );

  final String key;
  final String title;
  final String detail;

  /// The screen where the step is done.
  final String path;
  final bool done;

  /// What the school has, once done: "13 classes, 26 sections".
  final String? summary;

  /// What has to come first, while that is missing.
  final String? blockedBy;
}

/// Something worth setting up once the six steps are done. Not counted.
class SetupExtra {
  const SetupExtra({required this.title, required this.path, required this.detail});

  factory SetupExtra.fromJson(Map<String, dynamic> json) =>
      SetupExtra(title: json['title'] as String, path: json['path'] as String, detail: json['detail'] as String);

  final String title;
  final String path;
  final String detail;
}

class SetupGuide {
  const SetupGuide({
    required this.schoolName,
    required this.closed,
    required this.done,
    required this.total,
    required this.steps,
    required this.extras,
  });

  factory SetupGuide.fromJson(Map<String, dynamic> json) => SetupGuide(
    schoolName: json['school_name'] as String,
    closed: json['closed'] as bool,
    done: json['done'] as int,
    total: json['total'] as int,
    steps: [for (final row in json['steps'] as List) SetupStep.fromJson(row as Map<String, dynamic>)],
    extras: [for (final row in json['extras'] as List) SetupExtra.fromJson(row as Map<String, dynamic>)],
  );

  final String schoolName;

  /// Finished or hidden - remembered for the whole school.
  final bool closed;
  final int done;
  final int total;
  final List<SetupStep> steps;
  final List<SetupExtra> extras;

  bool get finished => done == total;

  /// The first step not yet done, if any.
  SetupStep? get next => steps.where((step) => !step.done).firstOrNull;

  /// A brand-new school: not even a year yet.
  bool get justStarted => steps.isNotEmpty && !steps.first.done;
}

/// A common department Quick add offers, and whether it starts ticked.
class DepartmentPreset {
  const DepartmentPreset({required this.name, required this.selected});

  factory DepartmentPreset.fromJson(Map<String, dynamic> json) =>
      DepartmentPreset(name: json['name'] as String, selected: json['selected'] as bool);

  final String name;
  final bool selected;
}

class QuickDepartmentsResult {
  const QuickDepartmentsResult({required this.created, required this.skipped});

  factory QuickDepartmentsResult.fromJson(Map<String, dynamic> json) => QuickDepartmentsResult(
    created: [for (final name in json['created'] as List) name as String],
    skipped: [for (final name in json['skipped'] as List) name as String],
  );

  final List<String> created;
  final List<String> skipped;
}

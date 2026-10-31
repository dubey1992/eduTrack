/// What Quick setup offers: the standard classes in order, and which are
/// ticked to start with (Nursery to Class 10).
class QuickSetupOption {
  const QuickSetupOption({required this.name, required this.level, required this.selected});

  factory QuickSetupOption.fromJson(Map<String, dynamic> json) =>
      QuickSetupOption(name: json['name'] as String, level: json['level'] as int, selected: json['selected'] as bool);

  final String name;
  final int level;
  final bool selected;
}

class QuickSetupOptions {
  const QuickSetupOptions({required this.classes, required this.sectionsMax});

  factory QuickSetupOptions.fromJson(Map<String, dynamic> json) => QuickSetupOptions(
    classes: [for (final row in json['classes'] as List) QuickSetupOption.fromJson(row as Map<String, dynamic>)],
    sectionsMax: json['sections_max'] as int,
  );

  final List<QuickSetupOption> classes;
  final int sectionsMax;
}

/// What a Quick setup did: the classes it made, the ones the year already had.
class QuickSetupResult {
  const QuickSetupResult({required this.created, required this.skipped, required this.sections});

  factory QuickSetupResult.fromJson(Map<String, dynamic> json) => QuickSetupResult(
    created: [for (final name in json['created'] as List) name as String],
    skipped: [for (final name in json['skipped'] as List) name as String],
    sections: [for (final name in json['sections'] as List) name as String],
  );

  final List<String> created;
  final List<String> skipped;
  final List<String> sections;
}

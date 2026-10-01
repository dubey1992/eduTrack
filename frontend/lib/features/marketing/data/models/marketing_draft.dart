import '../marketing_defaults.dart';

/// What the homepage could say, what it says now, and the form to say it
/// in (docs/marketing-content.md, slice 2).
///
/// The form is not written out in Dart. The server declares every section
/// and field, including how long each may be and whether it takes more
/// than one line, and the editor draws whatever comes back - so adding a
/// field to the page is one entry on the server rather than two screens
/// kept in step by hand.
class MarketingDraft {
  const MarketingDraft({
    required this.sections,
    required this.draft,
    required this.published,
    required this.publishedAt,
    required this.hasUnpublishedChanges,
  });

  factory MarketingDraft.fromJson(Map<String, dynamic> json) {
    final sections = json['sections'];
    final publishedAt = json['published_at'];

    return MarketingDraft(
      sections: [
        if (sections is List)
          for (final section in sections)
            if (section is Map<String, dynamic>) MarketingSection.fromJson(section),
      ],
      draft: _words(json['draft']),
      published: _words(json['published']),
      publishedAt: publishedAt is String ? DateTime.tryParse(publishedAt)?.toLocal() : null,
      hasUnpublishedChanges: json['has_unpublished_changes'] == true,
    );
  }

  final List<MarketingSection> sections;

  /// What is being worked on - only the fields somebody changed.
  final Map<String, String> draft;

  /// What visitors are reading right now.
  final Map<String, String> published;

  final DateTime? publishedAt;

  final bool hasUnpublishedChanges;

  List<MarketingField> get fields => [for (final section in sections) ...section.fields];

  static Map<String, String> _words(Object? value) {
    if (value is! Map) return const {};

    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
    };
  }
}

class MarketingSection {
  const MarketingSection({required this.key, required this.label, required this.description, required this.fields});

  factory MarketingSection.fromJson(Map<String, dynamic> json) {
    final fields = json['fields'];

    return MarketingSection(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
      fields: [
        if (fields is List)
          for (final field in fields)
            if (field is Map<String, dynamic>) MarketingField.fromJson(field),
      ],
    );
  }

  final String key;
  final String label;
  final String description;
  final List<MarketingField> fields;
}

class MarketingField {
  const MarketingField({
    required this.key,
    required this.label,
    required this.multiline,
    required this.maxLength,
    required this.help,
  });

  factory MarketingField.fromJson(Map<String, dynamic> json) {
    final maxLength = json['max_length'];

    return MarketingField(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      multiline: json['multiline'] == true,
      maxLength: maxLength is int && maxLength > 0 ? maxLength : 120,
      help: json['help'] as String? ?? '',
    );
  }

  final String key;
  final String label;
  final bool multiline;
  final int maxLength;
  final String help;

  /// The words the page shows when this field is left alone - the copy
  /// that ships, which is what the editor uses as the box's placeholder so
  /// an empty box still says what the visitor will read.
  String get shipped => marketingDefaults[key] ?? '';
}

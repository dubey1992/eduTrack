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
    this.draftLists = const {},
    this.figures = const {},
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
      draftLists: _lists(json['draft']),
      figures: _figures(json['figures']),
      published: _words(json['published']),
      publishedAt: publishedAt is String ? DateTime.tryParse(publishedAt)?.toLocal() : null,
      hasUnpublishedChanges: json['has_unpublished_changes'] == true,
    );
  }

  final List<MarketingSection> sections;

  /// What is being worked on - only the fields somebody changed.
  final Map<String, String> draft;

  /// The repeating lists somebody changed. A list absent here is the one
  /// the page ships with, so the editor starts from that.
  final Map<String, List<Map<String, String>>> draftLists;

  /// What visitors are reading right now.
  final Map<String, String> published;

  final DateTime? publishedAt;

  final bool hasUnpublishedChanges;

  /// What a live figure would say if it were published now - so the editor
  /// can show the real number beside the choice, and the preview can draw
  /// it. The public page is never told which figures are live; it is handed
  /// numbers already resolved.
  final Map<String, int> figures;

  List<MarketingField> get fields => [for (final section in sections) ...section.fields];

  List<MarketingListField> get listFields => [for (final section in sections) ...section.lists];

  /// The items the editor should show for [key]: what somebody saved, or
  /// the list the page ships with when they have not touched it.
  List<Map<String, String>> itemsFor(String key) {
    final saved = draftLists[key];

    if (saved != null && saved.isNotEmpty) return saved;

    return marketingListDefaults[key] ?? const [];
  }

  static Map<String, int> _figures(Object? value) {
    if (value is! Map) return const {};

    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is int) entry.key as String: entry.value as int,
    };
  }

  static Map<String, List<Map<String, String>>> _lists(Object? value) {
    if (value is! Map) return const {};

    final lists = <String, List<Map<String, String>>>{};

    for (final entry in value.entries) {
      if (entry.key is! String || entry.value is! List) continue;

      lists[entry.key as String] = [
        for (final item in entry.value as List)
          if (item is Map)
            {
              for (final field in item.entries)
                if (field.key is String && field.value is String) field.key as String: field.value as String,
            },
      ];
    }

    return lists;
  }

  static Map<String, String> _words(Object? value) {
    if (value is! Map) return const {};

    return {
      for (final entry in value.entries)
        if (entry.key is String && entry.value is String) entry.key as String: entry.value as String,
    };
  }
}

class MarketingSection {
  const MarketingSection({
    required this.key,
    required this.label,
    required this.description,
    required this.fields,
    this.lists = const [],
  });

  factory MarketingSection.fromJson(Map<String, dynamic> json) {
    final fields = json['fields'];
    final lists = json['lists'];

    return MarketingSection(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      description: json['description'] as String? ?? '',
      fields: [
        if (fields is List)
          for (final field in fields)
            if (field is Map<String, dynamic>) MarketingField.fromJson(field),
      ],
      lists: [
        if (lists is List)
          for (final declared in lists)
            if (declared is Map<String, dynamic>) MarketingListField.fromJson(declared),
      ],
    );
  }

  final String key;
  final String label;
  final String description;
  final List<MarketingField> fields;
  final List<MarketingListField> lists;
}

/// One repeating list - the feature cards, the figures under the hero, the
/// ticked list, a footer column.
///
/// [minItems] and [maxItems] are the layout rather than storage: the hero
/// holds five figures across its width, the features grid three rows of
/// five. The editor stops somebody adding a sixth figure rather than
/// letting them publish a row that wraps badly.
class MarketingListField {
  const MarketingListField({
    required this.key,
    required this.label,
    required this.itemLabel,
    required this.help,
    required this.fields,
    required this.minItems,
    required this.maxItems,
  });

  factory MarketingListField.fromJson(Map<String, dynamic> json) {
    final fields = json['fields'];
    final min = json['min_items'];
    final max = json['max_items'];

    return MarketingListField(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      itemLabel: json['item_label'] as String? ?? 'Item',
      help: json['help'] as String? ?? '',
      fields: [
        if (fields is List)
          for (final field in fields)
            if (field is Map<String, dynamic>) MarketingItemField.fromJson(field),
      ],
      minItems: min is int && min > 0 ? min : 1,
      maxItems: max is int && max > 0 ? max : 10,
    );
  }

  final String key;
  final String label;
  final String itemLabel;
  final String help;
  final List<MarketingItemField> fields;
  final int minItems;
  final int maxItems;

  /// The list the page ships with - what the editor starts from when
  /// nobody has changed it.
  List<Map<String, String>> get shipped => marketingListDefaults[key] ?? const [];

  Map<String, String> get blankItem => {for (final field in fields) field.key: field.firstChoice};

  /// The address box, if this list has one - the footer's columns do.
  bool get hasAddresses => fields.any((field) => field.key == 'url');
}

/// One box inside a repeating item. [choices] turns it into a picker.
class MarketingItemField {
  const MarketingItemField({
    required this.key,
    required this.label,
    required this.maxLength,
    required this.help,
    required this.choices,
    this.required = true,
  });

  factory MarketingItemField.fromJson(Map<String, dynamic> json) {
    final maxLength = json['max_length'];
    final choices = json['choices'];

    return MarketingItemField(
      key: json['key'] as String? ?? '',
      label: json['label'] as String? ?? '',
      maxLength: maxLength is int && maxLength > 0 ? maxLength : 60,
      help: json['help'] as String? ?? '',
      choices: [
        if (choices is List)
          for (final choice in choices)
            if (choice is Map<String, dynamic>) MarketingChoice.fromJson(choice),
      ],
      // Absent means required - the safer reading of a declaration this
      // build does not fully understand.
      required: json['required'] != false,
    );
  }

  final String key;
  final String label;
  final int maxLength;
  final String help;
  final List<MarketingChoice> choices;

  /// A blank required box is a hole in the page - a card with no title.
  /// An optional one is a real choice: a footer line with no address is
  /// the plain text it has always been.
  final bool required;

  /// What a newly added item gets: the first thing on the picker, or an
  /// empty box for somebody to fill in.
  String get firstChoice => choices.isEmpty ? '' : choices.first.value;
}

class MarketingChoice {
  const MarketingChoice({required this.value, required this.label});

  factory MarketingChoice.fromJson(Map<String, dynamic> json) {
    return MarketingChoice(value: json['value'] as String? ?? '', label: json['label'] as String? ?? '');
  }

  final String value;
  final String label;
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

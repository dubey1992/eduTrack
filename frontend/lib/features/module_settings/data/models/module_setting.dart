/// What kind of value a module setting holds, as the registry declares it.
enum SettingFieldType {
  flag('bool'),
  integer('int');

  const SettingFieldType(this.apiValue);

  final String apiValue;

  static SettingFieldType fromApiValue(String value) {
    return SettingFieldType.values.firstWhere((t) => t.apiValue == value, orElse: () => SettingFieldType.integer);
  }
}

/// One setting a module declares: its key, how to show it, and the range
/// the server will accept. The form is built from these, so a new setting
/// on the backend shows up here without a client change.
class SettingField {
  const SettingField({
    required this.key,
    required this.label,
    required this.type,
    required this.defaultValue,
    this.help,
    this.min,
    this.max,
  });

  factory SettingField.fromJson(Map<String, dynamic> json) {
    return SettingField(
      key: json['key'] as String,
      label: json['label'] as String,
      type: SettingFieldType.fromApiValue(json['type'] as String? ?? 'int'),
      defaultValue: json['default'],
      help: json['help'] as String?,
      min: json['min'] as int?,
      max: json['max'] as int?,
    );
  }

  final String key;
  final String label;
  final SettingFieldType type;
  final Object? defaultValue;
  final String? help;
  final int? min;
  final int? max;
}

/// One module as the school sees it: the two switches (the platform grants
/// it, the school keeps it on), and its own settings with the schema that
/// says how to edit them. A module with [switchable] false is part of the
/// spine and is always on.
class ModuleSetting {
  const ModuleSetting({
    required this.module,
    required this.label,
    required this.description,
    required this.switchable,
    required this.platformEnabled,
    required this.schoolEnabled,
    required this.enabled,
    required this.canChangePlatform,
    required this.settings,
    required this.settingsSchema,
    required this.updatedAt,
    required this.updatedByName,
  });

  factory ModuleSetting.fromJson(Map<String, dynamic> json) {
    final rawSettings = json['settings'];
    final rawSchema = json['settings_schema'];

    return ModuleSetting(
      module: json['module'] as String,
      label: json['label'] as String,
      description: json['description'] as String? ?? '',
      switchable: json['switchable'] as bool? ?? true,
      platformEnabled: json['platform_enabled'] as bool? ?? true,
      schoolEnabled: json['school_enabled'] as bool? ?? true,
      enabled: json['enabled'] as bool? ?? true,
      canChangePlatform: json['can_change_platform'] as bool? ?? false,
      settings: rawSettings is Map ? Map<String, Object?>.from(rawSettings) : const {},
      settingsSchema: rawSchema is List
          ? [for (final field in rawSchema) SettingField.fromJson(field as Map<String, dynamic>)]
          : const [],
      updatedAt: json['updated_at'] as String?,
      updatedByName: json['updated_by_name'] as String?,
    );
  }

  final String module;
  final String label;
  final String description;

  /// False for the spine (students, staff, academics, users, audit), which
  /// can never be switched off.
  final bool switchable;

  /// Whether the platform has granted the module to this school.
  final bool platformEnabled;

  /// Whether the school keeps it on. Only counts while [platformEnabled].
  final bool schoolEnabled;

  /// Both switches say yes.
  final bool enabled;

  /// True for the Super Admin, who is the only one to move the platform switch.
  final bool canChangePlatform;

  /// The values in force, keyed by [SettingField.key].
  final Map<String, Object?> settings;
  final List<SettingField> settingsSchema;
  final String? updatedAt;
  final String? updatedByName;

  bool get hasSettings => settingsSchema.isNotEmpty;

  /// The value in force for [field]: what the school saved, else the default.
  Object? valueOf(SettingField field) => settings.containsKey(field.key) ? settings[field.key] : field.defaultValue;
}

import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/module_settings/data/models/module_setting.dart';
import 'package:edutrack_app/features/module_settings/data/module_settings_repository.dart';

/// Test double for [ModuleSettingsRepository] - keeps one list of [rows]
/// the way the server would for one school and records what each update
/// was asked for.
class FakeModuleSettingsRepository implements ModuleSettingsRepository {
  FakeModuleSettingsRepository({List<ModuleSetting>? rows, this.failListWith, this.failUpdateWith})
    : rows = rows ?? defaultModuleSettings();

  List<ModuleSetting> rows;
  Failure? failListWith;
  Failure? failUpdateWith;

  /// When set, [list] waits on it - so a test can look at the loading state.
  Completer<void>? listGate;

  int listCalls = 0;
  int? lastListSchoolId;
  int updateCalls = 0;
  Map<String, Object?>? lastUpdate;

  @override
  Future<List<ModuleSetting>> list({int? schoolId}) async {
    listCalls++;
    lastListSchoolId = schoolId;
    if (listGate != null) await listGate!.future;
    if (failListWith != null) throw failListWith!;
    return List.unmodifiable(rows);
  }

  @override
  Future<ModuleSetting> update(
    String module, {
    int? schoolId,
    bool? platformEnabled,
    bool? schoolEnabled,
    Map<String, Object?>? settings,
  }) async {
    updateCalls++;
    lastUpdate = {
      'module': module,
      'school_id': schoolId,
      'platform_enabled': platformEnabled,
      'school_enabled': schoolEnabled,
      'settings': settings,
    };
    if (failUpdateWith != null) throw failUpdateWith!;

    final existing = rows.firstWhere((row) => row.module == module);
    final updated = moduleSetting(
      module: existing.module,
      label: existing.label,
      description: existing.description,
      switchable: existing.switchable,
      platformEnabled: platformEnabled ?? existing.platformEnabled,
      schoolEnabled: schoolEnabled ?? existing.schoolEnabled,
      canChangePlatform: existing.canChangePlatform,
      settings: settings == null ? existing.settings : {...existing.settings, ...settings},
      settingsSchema: existing.settingsSchema,
      updatedAt: '2026-09-19T05:30:00Z',
      updatedByName: 'Anita Sharma',
    );
    rows = [for (final row in rows) row.module == module ? updated : row];
    return updated;
  }
}

/// One module row; override only what a test is about. [enabled] follows
/// the two switches the way the server computes it.
ModuleSetting moduleSetting({
  String module = 'attendance',
  String label = 'Student Attendance',
  String description = 'Daily registers, per section.',
  bool switchable = true,
  bool platformEnabled = true,
  bool schoolEnabled = true,
  bool canChangePlatform = true,
  Map<String, Object?> settings = const {},
  List<SettingField> settingsSchema = const [],
  String? updatedAt,
  String? updatedByName,
}) {
  return ModuleSetting(
    module: module,
    label: label,
    description: description,
    switchable: switchable,
    platformEnabled: platformEnabled,
    schoolEnabled: schoolEnabled,
    enabled: platformEnabled && schoolEnabled,
    canChangePlatform: canChangePlatform,
    settings: settings,
    settingsSchema: settingsSchema,
    updatedAt: updatedAt,
    updatedByName: updatedByName,
  );
}

const lateDaysField = SettingField(
  key: 'late_days',
  label: 'Days a register may be marked late',
  type: SettingFieldType.integer,
  defaultValue: 30,
  help: '0 means today only.',
  min: 0,
  max: 365,
);

const emailPayslipsField = SettingField(
  key: 'email_payslips',
  label: 'Email payslips when a run is finalized',
  type: SettingFieldType.flag,
  defaultValue: true,
);

/// A spine module, a switchable one with a number setting, one with a flag
/// setting and one with none - enough to exercise every kind of card, as
/// the Super Admin sees them ([canChangePlatform] true).
List<ModuleSetting> defaultModuleSettings({bool canChangePlatform = true}) {
  return [
    moduleSetting(
      module: 'students',
      label: 'Students',
      description: 'The school roll.',
      switchable: false,
      canChangePlatform: canChangePlatform,
    ),
    moduleSetting(
      settings: const {'late_days': 30},
      settingsSchema: const [lateDaysField],
      canChangePlatform: canChangePlatform,
    ),
    moduleSetting(
      module: 'payroll',
      label: 'Payroll',
      description: 'Salary runs and payslips.',
      settings: const {'email_payslips': true},
      settingsSchema: const [emailPayslipsField],
      canChangePlatform: canChangePlatform,
    ),
    moduleSetting(
      module: 'timetable',
      label: 'Timetable',
      description: 'Periods and who teaches them.',
      canChangePlatform: canChangePlatform,
    ),
  ];
}

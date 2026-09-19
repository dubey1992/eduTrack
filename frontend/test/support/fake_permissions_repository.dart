import 'dart:async';

import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/permissions/data/models/permissions_matrix.dart';
import 'package:edutrack_app/features/permissions/data/permissions_repository.dart';

/// Test double for [PermissionsRepository] - keeps one [matrix] the way the
/// server would and records what each save was asked for.
class FakePermissionsRepository implements PermissionsRepository {
  FakePermissionsRepository({PermissionsMatrix? matrix, this.failGetWith, this.failSaveWith, this.failResetWith})
    : matrix = matrix ?? permissionsMatrix();

  PermissionsMatrix matrix;
  Failure? failGetWith;
  Failure? failSaveWith;
  Failure? failResetWith;

  /// When set, [get] waits on it - so a test can look at the loading state.
  Completer<void>? getGate;

  int getCalls = 0;
  int saveCalls = 0;
  int resetCalls = 0;

  /// The last save's cells as they went over the wire: {role: {module: level}}.
  Map<String, Map<String, String>>? lastSave;

  @override
  Future<PermissionsMatrix> get() async {
    getCalls++;
    if (getGate != null) await getGate!.future;
    if (failGetWith != null) throw failGetWith!;
    return matrix;
  }

  @override
  Future<PermissionsMatrix> save(LevelGrid changes) async {
    saveCalls++;
    lastSave = {
      for (final role in changes.entries)
        role.key: {for (final cell in role.value.entries) cell.key: cell.value.apiValue},
    };
    if (failSaveWith != null) throw failSaveWith!;

    final merged = <String, Map<String, PermissionLevel>>{
      for (final role in matrix.matrix.entries) role.key: Map.of(role.value),
    };
    for (final role in changes.entries) {
      merged.putIfAbsent(role.key, () => {}).addAll(role.value);
    }
    matrix = permissionsMatrix(canEdit: matrix.canEdit, matrix: merged);
    return matrix;
  }

  @override
  Future<PermissionsMatrix> reset() async {
    resetCalls++;
    if (failResetWith != null) throw failResetWith!;

    matrix = permissionsMatrix(canEdit: matrix.canEdit);
    return matrix;
  }
}

const permissionRoles = [
  PermissionRole(value: 'SCHOOL_ADMIN', label: 'School Admin'),
  PermissionRole(value: 'HOD', label: 'HOD'),
  PermissionRole(value: 'TEACHER', label: 'Teacher'),
];

const permissionModules = [
  PermissionModule(value: 'students', label: 'Students', description: 'The school roll.'),
  PermissionModule(value: 'attendance', label: 'Student Attendance', description: 'Daily registers.'),
  PermissionModule(value: 'timetable', label: 'Timetable', description: 'Periods and who teaches them.'),
];

/// The shipped defaults for the three roles and three modules above, as
/// docs/settings.md lists them.
const LevelGrid permissionDefaults = {
  'SCHOOL_ADMIN': {
    'students': PermissionLevel.manage,
    'attendance': PermissionLevel.manage,
    'timetable': PermissionLevel.manage,
  },
  'HOD': {'students': PermissionLevel.none, 'attendance': PermissionLevel.none, 'timetable': PermissionLevel.view},
  'TEACHER': {
    'students': PermissionLevel.view,
    'attendance': PermissionLevel.manage,
    'timetable': PermissionLevel.view,
  },
};

/// A matrix at its defaults unless [matrix] says otherwise.
PermissionsMatrix permissionsMatrix({bool canEdit = true, LevelGrid? matrix}) {
  return PermissionsMatrix(
    roles: permissionRoles,
    modules: permissionModules,
    levels: PermissionLevel.values,
    matrix: matrix ?? permissionDefaults,
    defaults: permissionDefaults,
    canEdit: canEdit,
  );
}

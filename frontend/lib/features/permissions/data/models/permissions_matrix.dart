import '../../../../core/models/permission_level.dart';

export '../../../../core/models/permission_level.dart';

/// How a cell's level reads on the Permissions screen.
extension PermissionLevelLabel on PermissionLevel {
  String get label => switch (this) {
    PermissionLevel.none => 'None',
    PermissionLevel.view => 'View',
    PermissionLevel.manage => 'Manage',
  };
}

/// A column of the matrix.
class PermissionRole {
  const PermissionRole({required this.value, required this.label});

  factory PermissionRole.fromJson(Map<String, dynamic> json) {
    return PermissionRole(value: json['value'] as String, label: json['label'] as String);
  }

  /// The role's API name, e.g. SCHOOL_ADMIN.
  final String value;
  final String label;
}

/// A row of the matrix.
class PermissionModule {
  const PermissionModule({required this.value, required this.label, required this.description});

  factory PermissionModule.fromJson(Map<String, dynamic> json) {
    return PermissionModule(
      value: json['value'] as String,
      label: json['label'] as String,
      description: json['description'] as String? ?? '',
    );
  }

  /// The module's key, e.g. students.
  final String value;
  final String label;
  final String description;
}

/// {role: {module: level}} - the shape of both the matrix and its defaults.
typedef LevelGrid = Map<String, Map<String, PermissionLevel>>;

/// The platform-wide matrix as the server sends it: the roles and modules
/// in display order, every cell's level, what each cell would be by
/// default, and whether the viewer may change any of it.
class PermissionsMatrix {
  const PermissionsMatrix({
    required this.roles,
    required this.modules,
    required this.levels,
    required this.matrix,
    required this.defaults,
    required this.canEdit,
  });

  factory PermissionsMatrix.fromJson(Map<String, dynamic> json) {
    final rawLevels = json['levels'] as List? ?? const [];

    return PermissionsMatrix(
      roles: [for (final role in json['roles'] as List) PermissionRole.fromJson(role as Map<String, dynamic>)],
      modules: [
        for (final module in json['modules'] as List) PermissionModule.fromJson(module as Map<String, dynamic>),
      ],
      levels: rawLevels.isEmpty
          ? PermissionLevel.values
          : [for (final level in rawLevels) PermissionLevel.fromApiValue((level as Map)['value'] as String)],
      matrix: _gridFromJson(json['matrix']),
      defaults: _gridFromJson(json['defaults']),
      canEdit: json['can_edit'] as bool? ?? false,
    );
  }

  static LevelGrid _gridFromJson(Object? raw) {
    if (raw is! Map) return const {};

    return {
      for (final entry in raw.entries)
        entry.key as String: {
          for (final cell in (entry.value as Map).entries)
            cell.key as String: PermissionLevel.fromApiValue(cell.value as String),
        },
    };
  }

  final List<PermissionRole> roles;
  final List<PermissionModule> modules;

  /// The levels a cell may take, in the order to offer them.
  final List<PermissionLevel> levels;
  final LevelGrid matrix;
  final LevelGrid defaults;

  /// True for the Super Admin only; everybody else reads.
  final bool canEdit;

  PermissionLevel levelOf(String role, String module) => matrix[role]?[module] ?? PermissionLevel.none;

  PermissionLevel defaultOf(String role, String module) => defaults[role]?[module] ?? PermissionLevel.none;
}

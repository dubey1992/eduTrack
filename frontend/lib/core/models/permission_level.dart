/// What a role may do in a module - one cell of the roles & permissions
/// matrix (docs/settings.md). Mirrors the backend's school/permissions.py.
enum PermissionLevel {
  none('none'),
  view('view'),
  manage('manage');

  const PermissionLevel(this.apiValue);

  final String apiValue;

  /// Whether this level grants at least [other]: manage includes view.
  bool atLeast(PermissionLevel other) => index >= other.index;

  static PermissionLevel fromApiValue(String value) {
    return PermissionLevel.values.firstWhere(
      (level) => level.apiValue == value,
      orElse: () => throw ArgumentError('Unknown permission level: $value'),
    );
  }
}

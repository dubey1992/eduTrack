/// A kind of fee a school charges - Tuition, Admission, Exam (docs/fees.md).
class FeeHead {
  const FeeHead({
    required this.id,
    required this.schoolId,
    required this.name,
    required this.isTransport,
    required this.isActive,
    required this.structuresCount,
  });

  factory FeeHead.fromJson(Map<String, dynamic> json) {
    return FeeHead(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      name: json['name'] as String,
      isTransport: json['is_transport'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      structuresCount: json['structures_count'] as int? ?? 0,
    );
  }

  final int id;
  final int schoolId;
  final String name;

  /// The one head every school has, which bus route fees are charged under.
  /// It cannot be renamed, retired or deleted.
  final bool isTransport;

  /// A retired head stays on the fees already set up with it, and cannot be
  /// chosen for a new one.
  final bool isActive;

  /// How many class and route fees use it. A head in use cannot be deleted.
  final int structuresCount;
}

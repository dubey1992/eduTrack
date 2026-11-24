/// A request this parent made for another guardian of their child, and the
/// school's answer (docs/mobile-apps-review.md, M8, 8.5).
class FamilyGuardianInvite {
  const FamilyGuardianInvite({required this.id, required this.name, required this.relationship, required this.status});

  factory FamilyGuardianInvite.fromJson(Map<String, dynamic> json) => FamilyGuardianInvite(
    id: json['id'] as int,
    name: json['name'] as String,
    relationship: json['relationship'] as String,
    status: json['status'] as String,
  );

  final int id;
  final String name;

  /// mother, father, guardian or other.
  final String relationship;

  /// pending, approved or declined.
  final String status;

  String get statusLabel => switch (status) {
    'approved' => 'Approved - the school will give them a set-up letter',
    'declined' => 'Declined by the school',
    _ => 'Waiting for the school',
  };
}

/// How a guardian is related, as the school records it.
const guardianRelationships = {'mother': 'Mother', 'father': 'Father', 'guardian': 'Guardian', 'other': 'Other'};

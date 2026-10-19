/// Where the schools are (docs/maps.md, M1d).
///
/// Deliberately not a [School]: a pin needs seven fields, and the list's
/// model carries thirty. Fetching the whole thing for every school on the
/// platform to draw a dot would be a page of data per dot.
class SchoolPin {
  const SchoolPin({
    required this.id,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.isBranch,
    required this.isActive,
    required this.city,
  });

  /// Null when the row is not a pin: no coordinates, half a pair, or
  /// numbers that are not numbers. A school like that belongs in the
  /// "not placed yet" list, never silently at (0, 0) off the coast of
  /// Africa - which is where a careless parse puts it.
  static SchoolPin? fromJson(Map<String, dynamic> json) {
    final id = json['id'];
    final latitude = double.tryParse('${json['latitude']}');
    final longitude = double.tryParse('${json['longitude']}');

    if (id is! int) return null;
    if (latitude == null || longitude == null) return null;
    if (latitude.abs() > 90 || longitude.abs() > 180) return null;

    return SchoolPin(
      id: id,
      name: json['name'] as String? ?? '',
      latitude: latitude,
      longitude: longitude,
      isBranch: json['is_branch'] == true,
      // Anything other than the word "active" is treated as not active: a
      // status this build does not recognise is not a reason to draw a
      // school as though nothing were wrong with it.
      isActive: json['status'] == 'active',
      city: json['city'] as String? ?? '',
    );
  }

  final int id;
  final String name;
  final double latitude;
  final double longitude;

  /// Branches are drawn in a different colour from the schools that head a
  /// group, which is most of what a group's map is for.
  final bool isBranch;

  final bool isActive;
  final String city;
}

/// A school that has no place on the map yet - the work the map exists to
/// prompt, so it is listed beside it rather than left out.
class UnplacedSchool {
  const UnplacedSchool({required this.id, required this.name});

  static UnplacedSchool? fromJson(Map<String, dynamic> json) {
    final id = json['id'];

    if (id is! int) return null;

    return UnplacedSchool(id: id, name: json['name'] as String? ?? '');
  }

  final int id;
  final String name;
}

class SchoolLocations {
  const SchoolLocations({required this.placed, required this.unplaced, required this.moreThanShown});

  const SchoolLocations.empty() : placed = const [], unplaced = const [], moreThanShown = false;

  factory SchoolLocations.fromJson(Map<String, dynamic> json) {
    final placed = <SchoolPin>[];
    final unplaced = <UnplacedSchool>[];

    for (final row in _rows(json['placed'])) {
      if (row is! Map<String, dynamic>) continue;

      final pin = SchoolPin.fromJson(row);

      // A row the server called placed but which does not parse as a point
      // is still a school somebody has to deal with, so it moves across
      // rather than disappearing.
      if (pin != null) {
        placed.add(pin);
      } else {
        final unparseable = UnplacedSchool.fromJson(row);
        if (unparseable != null) unplaced.add(unparseable);
      }
    }

    for (final row in _rows(json['unplaced'])) {
      if (row is! Map<String, dynamic>) continue;

      final school = UnplacedSchool.fromJson(row);
      if (school != null) unplaced.add(school);
    }

    return SchoolLocations(placed: placed, unplaced: unplaced, moreThanShown: json['more_than_shown'] == true);
  }

  /// A list, or nothing at all.
  ///
  /// `as List?` is not this: it throws for anything that is neither a list
  /// nor null, so one unexpected field would take down a screen that is
  /// otherwise perfectly able to show what it did understand.
  static List<dynamic> _rows(Object? value) => value is List ? value : const [];

  final List<SchoolPin> placed;
  final List<UnplacedSchool> unplaced;

  /// The platform has outgrown one map of itself. Said out loud, because a
  /// map quietly showing some of the schools is worse than one that admits
  /// it is showing some of them.
  final bool moreThanShown;

  bool get isEmpty => placed.isEmpty && unplaced.isEmpty;
}

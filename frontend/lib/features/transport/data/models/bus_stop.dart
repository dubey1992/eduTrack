import '../../../../core/network/paginated_response.dart';

/// A page of the list, plus the one thing that is not on it.
///
/// The screen draws a map and has to centre it before there is a single
/// stop to frame - and the people who keep this list cannot read /schools
/// at all: a Transport Manager answers for their own school without being
/// able to list schools. So the page carries where the school is.
class BusStopPage {
  const BusStopPage({
    required this.page,
    required this.schoolLatitude,
    required this.schoolLongitude,
    required this.schoolName,
  });

  factory BusStopPage.fromJson(Map<String, dynamic> json) {
    return BusStopPage(
      page: PaginatedResponse.fromJson(json, BusStop.fromJson),
      schoolLatitude: json['school_latitude'] as String?,
      schoolLongitude: json['school_longitude'] as String?,
      schoolName: json['school_name'] as String?,
    );
  }

  final PaginatedResponse<BusStop> page;

  /// Null when there is no single school to speak of - a Super Admin who
  /// has not picked one - or when nobody has placed it yet.
  final String? schoolLatitude;
  final String? schoolLongitude;

  /// What to call it when saying how far a stop is from it. The people who
  /// keep this list cannot read /schools to look the name up.
  final String? schoolName;
}

/// One place in the school's list of bus stops (docs/maps.md).
///
/// The place, not the call. A [TransportStop] is a route stopping somewhere
/// fourth at 07:15; this is the corner by the post office, which several
/// routes may call at and which somebody fixes the position of once.
class BusStop {
  const BusStop({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.landmark,
    required this.status,
    required this.routesCount,
  });

  factory BusStop.fromJson(Map<String, dynamic> json) {
    return BusStop(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String? ?? '',
      name: json['name'] as String,
      latitude: json['latitude'] as String,
      longitude: json['longitude'] as String,
      landmark: json['landmark'] as String?,
      status: json['status'] as String,
      routesCount: json['routes_count'] as int? ?? 0,
    );
  }

  final int id;
  final int schoolId;
  final String schoolName;
  final String name;

  /// Always there, unlike a route's stop: these are picked on a map, so a
  /// stop nobody can point to is not a stop.
  final String latitude;
  final String longitude;

  /// "Opposite the post office" - what somebody tells a parent on the
  /// phone. Often empty, because the name is usually enough.
  final String? landmark;

  final String status;

  /// How many routes call here. What makes a delete refusable, and what the
  /// screen says before anybody tries.
  final int routesCount;

  bool get isActive => status == 'active';

  bool get isOnARoute => routesCount > 0;
}

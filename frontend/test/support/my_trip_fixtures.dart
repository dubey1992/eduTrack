import 'package:dio/dio.dart';
import 'package:edutrack_app/features/my_trip/data/location_source.dart';
import 'package:edutrack_app/features/my_trip/data/models/location_point.dart';
import 'package:edutrack_app/features/my_trip/data/models/trip_mark.dart';
import 'package:edutrack_app/features/my_trip/data/my_trip_api.dart';
import 'package:edutrack_app/features/my_trip/data/phone_dialer.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';

/// A stop as the trip detail sends it.
Map<String, dynamic> stopJson(int id, String name, int sequence, {bool reached = false}) => {
  'id': id,
  'name': name,
  'sequence_number': sequence,
  'pickup_time': '07:${10 + sequence}',
  'drop_time': '15:${10 + sequence}',
  'latitude': null,
  'longitude': null,
  'reached': reached,
};

/// A rider as the trip detail sends it.
Map<String, dynamic> riderJson(
  int studentId,
  String name, {
  required int stopId,
  String status = 'pending',
  String? guardianMobile = '+91 98765 43210',
}) => {
  'student_id': studentId,
  'name': name,
  'admission_number': 'ADM-$studentId',
  'class_section_name': 'Class 5 - A',
  'guardian_name': 'Parent of $name',
  'guardian_mobile': guardianMobile,
  'stop_id': stopId,
  'stop_name': 'Stop $stopId',
  'stop_sequence_number': stopId,
  'status': status,
  'boarded_at': null,
  'dropped_at': null,
  'boarded_at_label': null,
  'dropped_at_label': null,
};

/// A running pickup trip on route 7 with two stops: Aarav and Diya wait at
/// the first, Kabir at the second (with no guardian number on record).
Map<String, dynamic> tripJson({int id = 55, String status = 'in_progress', String direction = 'pickup'}) => {
  'id': id,
  'school_id': 1,
  'route_id': 7,
  'route_name': 'North Loop',
  'route_label': 'Bus 1 - North Loop',
  'vehicle_id': 3,
  'vehicle_name': 'Bus 1',
  'vehicle_registration_number': 'KA-01-1234',
  'driver_id': 4,
  'driver_name': 'Ravi Driver',
  'driver_mobile': '+91 90000 00000',
  'trip_date': '2026-09-19',
  'direction': direction,
  'status': status,
  'current_stop_id': null,
  'current_stop_name': null,
  'started_by_name': 'Asha Attendant',
  'started_at': '2026-09-19T01:30:00Z',
  'ended_at': null,
  'started_at_label': '7:00 AM',
  'ended_at_label': null,
  'riders_count': 3,
  'stops': [stopJson(101, 'Main Gate', 1), stopJson(102, 'Lake Road', 2)],
  'riders': [
    riderJson(1, 'Aarav Sharma', stopId: 101),
    riderJson(2, 'Diya Patel', stopId: 101),
    riderJson(3, 'Kabir Rao', stopId: 102, guardianMobile: null),
  ],
  // The second is a kind no version of the app knows.
  'events': [
    {
      'id': 1,
      'type': 'started',
      'stop_id': null,
      'stop_name': null,
      'student_id': null,
      'student_name': null,
      'recorded_by_name': 'Asha',
      'recorded_at': '2026-09-19T01:30:00Z',
      'recorded_at_label': '7:00 AM',
      'note': null,
    },
    {
      'id': 2,
      'type': 'some_future_kind',
      'stop_id': null,
      'stop_name': null,
      'student_id': 1,
      'student_name': 'Aarav Sharma',
      'recorded_by_name': 'Asha',
      'recorded_at': '2026-09-19T01:31:00Z',
      'recorded_at_label': '7:01 AM',
      'note': null,
    },
  ],
};

/// GET /transport/my-routes with one route and today's trips as given.
Map<String, dynamic> myRoutesJson({Map<String, dynamic>? pickup, Map<String, dynamic>? drop}) => {
  'date': '2026-09-19',
  'routes': [
    {
      'id': 7,
      'name': 'North Loop',
      'label': 'Bus 1 - North Loop',
      'vehicle_name': 'Bus 1',
      'vehicle_registration_number': 'KA-01-1234',
      'driver_name': 'Ravi Driver',
      'driver_mobile': '+91 90000 00000',
      'attendant_user_id': 9,
      'attendant_name': 'Asha Attendant',
      'stops_count': 2,
      'students_count': 3,
      'today': {'pickup': pickup, 'drop': drop},
    },
  ],
};

DioException offlineError(String path) => DioException(
  requestOptions: RequestOptions(path: path),
  type: DioExceptionType.connectionError,
);

DioException apiError(String path, int status, String code, String message) {
  final options = RequestOptions(path: path);
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response(
      requestOptions: options,
      statusCode: status,
      data: {'code': code, 'message': message, 'details': <String, dynamic>{}},
    ),
  );
}

/// The attendant's endpoints, served from memory. The "server" trip moves as
/// marks are applied, so what a sync hands back is what the server would.
class FakeMyTripApi implements MyTripApi {
  FakeMyTripApi({Map<String, dynamic>? routes, Map<String, dynamic>? trip})
    : routes = routes ?? myRoutesJson(),
      serverTrip = trip ?? tripJson();

  Map<String, dynamic> routes;
  Map<String, dynamic> serverTrip;

  /// Every call fails as if there were no signal.
  bool offline = false;

  /// Mark type -> the reason the server turns it down with.
  Map<String, String> rejectTypes = {};

  /// Client ids the server has already recorded.
  final Set<String> alreadyRecorded = {};

  /// What POST /transport/trips answers with, or throws when set.
  DioException? startError;

  /// What POST .../locations throws, when set.
  DioException? locationsError;

  /// What POST .../sync throws, when set (a malformed batch, a trip gone).
  DioException? syncError;

  /// Every sync request, including those that failed for want of signal.
  int syncAttempts = 0;

  final List<List<Map<String, dynamic>>> syncBatches = [];
  final List<List<LocationPoint>> locationBatches = [];
  int startCalls = 0;

  List<Map<String, dynamic>> get syncedOps => syncBatches.expand((batch) => batch).toList();

  @override
  Future<Map<String, dynamic>> myRoutes() async {
    if (offline) throw offlineError('/transport/my-routes');
    return routes;
  }

  @override
  Future<Map<String, dynamic>> trip(int tripId) async {
    if (offline) throw offlineError('/transport/trips/$tripId');
    return serverTrip;
  }

  @override
  Future<Map<String, dynamic>> startTrip({required int routeId, required TripDirection direction}) async {
    startCalls++;
    if (offline) throw offlineError('/transport/trips');
    if (startError != null) throw startError!;

    serverTrip = tripJson(direction: direction.apiValue);
    routes = myRoutesJson(
      pickup: direction == TripDirection.pickup ? serverTrip : null,
      drop: direction == TripDirection.drop ? serverTrip : null,
    );
    return serverTrip;
  }

  @override
  Future<Map<String, dynamic>> sync(int tripId, List<TripMark> marks) async {
    syncAttempts++;
    if (offline) throw offlineError('/transport/trips/$tripId/sync');
    if (syncError != null) throw syncError!;

    final ops = marks.map((m) => m.toSyncJson()).toList();
    syncBatches.add(ops);

    final results = <Map<String, dynamic>>[];
    for (final op in ops) {
      final clientId = op['client_id'] as String;
      final reason = rejectTypes[op['type']];
      if (alreadyRecorded.contains(clientId)) {
        results.add({'client_id': clientId, 'type': op['type'], 'status': 'duplicate'});
      } else if (reason != null) {
        results.add({'client_id': clientId, 'type': op['type'], 'status': 'rejected', 'reason': reason});
      } else {
        _apply(op);
        alreadyRecorded.add(clientId);
        results.add({'client_id': clientId, 'type': op['type'], 'status': 'applied'});
      }
    }
    return {'results': results, 'trip': serverTrip};
  }

  @override
  Future<Map<String, dynamic>> sendLocations(int tripId, List<LocationPoint> points) async {
    if (offline) throw offlineError('/transport/trips/$tripId/locations');
    if (locationsError != null) throw locationsError!;

    locationBatches.add(points);
    return {'accepted': points.length, 'refused': 0};
  }

  void _apply(Map<String, dynamic> op) {
    final stops = (serverTrip['stops'] as List).cast<Map<String, dynamic>>();
    final riders = (serverTrip['riders'] as List).cast<Map<String, dynamic>>();

    switch (op['type']) {
      case 'stop_reached':
        for (final stop in stops) {
          if (stop['id'] == op['stop_id']) stop['reached'] = true;
        }
        serverTrip['current_stop_id'] = op['stop_id'];
      case 'boarded' || 'dropped' || 'absent':
        for (final rider in riders) {
          if (rider['student_id'] == op['student_id']) rider['status'] = op['type'];
        }
      case 'end':
        for (final rider in riders) {
          if (rider['status'] == 'pending') rider['status'] = 'absent';
        }
        serverTrip['status'] = 'completed';
    }
  }
}

/// A location source that always has a position unless told otherwise.
class FakeLocationSource implements LocationSource {
  FakeLocationSource({this.access = LocationAccess.granted});

  LocationAccess access;
  int positionsTaken = 0;

  @override
  Future<LocationAccess> requestAccess() async => access;

  @override
  Future<DevicePosition> currentPosition() async {
    if (access != LocationAccess.granted) throw LocationUnavailable(access);
    positionsTaken++;
    return DevicePosition(latitude: 12.97 + positionsTaken / 1000, longitude: 77.59, accuracy: 8, speed: 6.5);
  }
}

/// Records the numbers it was asked to dial instead of leaving the app.
class FakePhoneDialer implements PhoneDialer {
  FakePhoneDialer({this.opens = true});

  bool opens;
  final List<String> dialled = [];

  @override
  Future<bool> dial(String number) async {
    dialled.add(number);
    return opens;
  }
}

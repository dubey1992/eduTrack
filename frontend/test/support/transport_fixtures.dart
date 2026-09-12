import 'package:edutrack_app/features/transport/data/models/driver.dart';
import 'package:edutrack_app/features/transport/data/models/transport_route.dart';
import 'package:edutrack_app/features/transport/data/models/transport_status.dart';
import 'package:edutrack_app/features/transport/data/models/transport_trip.dart';
import 'package:edutrack_app/features/transport/data/models/vehicle.dart';

const bus04 = Vehicle(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Bus 04',
  registrationNumber: 'MH12 AB 1234',
  capacity: 40,
  status: TransportStatus.active,
  routeId: 1,
  routeName: 'Green Park',
);

const bus09Spare = Vehicle(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Bus 09',
  registrationNumber: 'MH12 CD 5678',
  capacity: 30,
  status: TransportStatus.active,
  routeId: null,
  routeName: null,
);

const sanjay = Driver(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Sanjay Patel',
  mobile: '+91 9876543210',
  licenceNumber: 'MH-12-20190012345',
  licenceExpiry: '2029-03-31',
  status: TransportStatus.active,
  routeId: 1,
  routeName: 'Green Park',
);

const expiredRamesh = Driver(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Ramesh Rao',
  mobile: null,
  licenceNumber: 'MH-12-20100099999',
  licenceExpiry: '2020-01-01',
  status: TransportStatus.active,
  routeId: null,
  routeName: null,
);

const lakeView = TransportStop(
  id: 101,
  routeId: 1,
  name: 'Lake View',
  sequenceNumber: 1,
  pickupTime: '07:30',
  dropTime: '15:30',
  studentsCount: 1,
);

const centralPark = TransportStop(
  id: 102,
  routeId: 1,
  name: 'Central Park',
  sequenceNumber: 2,
  pickupTime: '07:45',
  dropTime: null,
  studentsCount: 0,
);

const greenPark = TransportRoute(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Green Park',
  label: 'Bus 04 - Green Park',
  status: TransportStatus.active,
  vehicleId: 1,
  vehicleName: 'Bus 04',
  vehicleRegistrationNumber: 'MH12 AB 1234',
  capacity: 40,
  driverId: 1,
  driverName: 'Sanjay Patel',
  driverMobile: '+91 9876543210',
  stopsCount: 2,
  studentsCount: 1,
  stops: [lakeView, centralPark],
);

/// Green Park with every seat taken.
const greenParkFull = TransportRoute(
  id: 1,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Green Park',
  label: 'Bus 04 - Green Park',
  status: TransportStatus.active,
  vehicleId: 1,
  vehicleName: 'Bus 04',
  vehicleRegistrationNumber: 'MH12 AB 1234',
  capacity: 40,
  driverId: 1,
  driverName: 'Sanjay Patel',
  driverMobile: '+91 9876543210',
  stopsCount: 2,
  studentsCount: 40,
  stops: [lakeView, centralPark],
);

const lakeRoadNoVehicle = TransportRoute(
  id: 2,
  schoolId: 1,
  schoolName: 'Sunrise Public School',
  name: 'Lake Road',
  label: 'Lake Road',
  status: TransportStatus.active,
  vehicleId: null,
  vehicleName: null,
  vehicleRegistrationNumber: null,
  capacity: null,
  driverId: null,
  driverName: null,
  driverMobile: null,
  stopsCount: 0,
  studentsCount: 0,
);

const arjunTripRider = TripRider(
  studentId: 7,
  admissionNumber: 'STU-0042',
  name: 'Arjun Kumar',
  classSectionName: 'Grade 8 A',
  guardianName: 'Raj Kumar',
  guardianMobile: '+91 9999999999',
  stopId: 101,
  stopName: 'Lake View',
  stopSequenceNumber: 1,
  status: TripRiderStatus.pending,
  boardedAt: null,
  droppedAt: null,
);

const meeraTripRider = TripRider(
  studentId: 8,
  admissionNumber: 'STU-0045',
  name: 'Meera Singh',
  classSectionName: 'Grade 7 B',
  guardianName: 'Rohit Singh',
  guardianMobile: null,
  stopId: 102,
  stopName: 'Central Park',
  stopSequenceNumber: 2,
  status: TripRiderStatus.pending,
  boardedAt: null,
  droppedAt: null,
);

/// Green Park's morning trip, just started, nobody boarded yet.
const greenParkTrip = TransportTrip(
  id: 1,
  schoolId: 1,
  routeId: 1,
  routeName: 'Green Park',
  routeLabel: 'Bus 04 - Green Park',
  vehicleId: 1,
  vehicleName: 'Bus 04',
  vehicleRegistrationNumber: 'MH12 AB 1234',
  driverId: 1,
  driverName: 'Sanjay Patel',
  driverMobile: '+91 9876543210',
  tripDate: '2026-09-10',
  direction: TripDirection.pickup,
  status: TripStatus.inProgress,
  currentStopId: null,
  currentStopName: null,
  startedByName: 'Mohan',
  startedAt: '2026-09-10T07:32:00.000000Z',
  endedAt: null,
  ridersCount: 2,
  pendingCount: 2,
  boardedCount: 0,
  droppedCount: 0,
  absentCount: 0,
  stopsLeft: 2,
  stops: [
    TripStop(id: 101, name: 'Lake View', sequenceNumber: 1, pickupTime: '07:30', dropTime: '15:30', reached: false),
    TripStop(id: 102, name: 'Central Park', sequenceNumber: 2, pickupTime: '07:45', dropTime: null, reached: false),
  ],
  riders: [arjunTripRider, meeraTripRider],
  events: [
    TripEvent(
      id: 1,
      type: TripEventType.started,
      stopId: null,
      stopName: null,
      studentId: null,
      studentName: null,
      recordedByName: 'Mohan',
      recordedAt: '2026-09-10T07:32:00.000000Z',
      note: 'Trip started with 2 students expected',
    ),
  ],
);

const arjunRider = RouteStudent(
  studentId: 7,
  admissionNumber: 'STU-0042',
  name: 'Arjun Kumar',
  classSectionName: 'Grade 8 A',
  guardianName: 'Raj Kumar',
  guardianMobile: '+91 9999999999',
  stopId: 101,
  stopName: 'Lake View',
  stopSequenceNumber: 1,
);

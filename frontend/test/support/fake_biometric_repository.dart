import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/biometric/data/biometric_repository.dart';
import 'package:edutrack_app/features/biometric/data/models/biometric_device.dart';
import 'package:edutrack_app/features/biometric/data/models/biometric_punch.dart';

/// The fingerprint readers a school has, and what they recorded
/// (docs/biometric.md).
class FakeBiometricRepository implements BiometricRepository {
  FakeBiometricRepository({List<BiometricDevice>? devices, List<BiometricPunch>? punches, this.unmatchedTotal = 0})
    : _devices = devices ?? [],
      _punches = punches ?? [];

  List<BiometricDevice> _devices;
  final List<BiometricPunch> _punches;

  String? lastQuery;
  int? lastSchoolFilter;
  Failure? failListWith;
  final List<Map<String, Object?>> created = [];
  final List<Map<String, Object?>> edited = [];
  final List<int> removed = [];

  // -- the punch log --
  int unmatchedTotal;
  String? lastPunchQuery;
  int? lastPunchSchoolFilter;
  bool lastUnmatchedOnly = false;
  Failure? failPunchesWith;
  Failure? failUploadWith;
  final List<Map<String, Object?>> uploaded = [];
  PunchUploadResult uploadResult = const PunchUploadResult(read: 0, accepted: 0, duplicate: 0, refused: []);

  @override
  Future<PaginatedResponse<BiometricDevice>> listDevices({
    int? schoolId,
    required int page,
    required int perPage,
    String? q,
    String? status,
  }) async {
    if (failListWith != null) throw failListWith!;

    lastQuery = q;
    lastSchoolFilter = schoolId;

    var rows = _devices;

    if (q != null && q.isNotEmpty) {
      rows = rows.where((d) => '${d.name} ${d.serialNumber} ${d.location}'.toLowerCase().contains(q)).toList();
    }

    return PaginatedResponse(items: rows, currentPage: 1, lastPage: 1, total: rows.length, perPage: perPage);
  }

  @override
  Future<BiometricDevice> createDevice({
    int? schoolId,
    required String name,
    required String serialNumber,
    String? location,
    String? pushKey,
  }) async {
    created.add({
      'school_id': schoolId,
      'name': name,
      'serial_number': serialNumber,
      'location': location,
      'push_key': pushKey,
    });

    final made = BiometricDevice(
      id: _devices.length + 1,
      schoolId: schoolId ?? 1,
      schoolName: 'Abbey Road School',
      serialNumber: serialNumber,
      name: name,
      location: location,
      status: 'active',
      lastSeenAt: null,
    );
    _devices = [..._devices, made];

    return made;
  }

  @override
  Future<BiometricDevice> updateDevice(
    int deviceId, {
    String? name,
    String? serialNumber,
    String? location,
    String? pushKey,
  }) async {
    edited.add({
      'id': deviceId,
      'name': name,
      'serial_number': serialNumber,
      'location': location,
      'push_key': pushKey,
    });

    return _devices.firstWhere((d) => d.id == deviceId);
  }

  @override
  Future<void> deleteDevice(int deviceId) async {
    removed.add(deviceId);
    _devices = _devices.where((d) => d.id != deviceId).toList();
  }

  @override
  Future<PunchPage> listPunches({
    int? schoolId,
    required int page,
    required int perPage,
    String? q,
    String? date,
    bool unmatchedOnly = false,
  }) async {
    if (failPunchesWith != null) throw failPunchesWith!;

    lastPunchQuery = q;
    lastPunchSchoolFilter = schoolId;
    lastUnmatchedOnly = unmatchedOnly;

    var rows = _punches;

    if (q != null && q.isNotEmpty) {
      rows = rows
          .where((p) => '${p.staffName} ${p.employeeId} ${p.biometricUserId}'.toLowerCase().contains(q.toLowerCase()))
          .toList();
    }

    if (unmatchedOnly) rows = rows.where((p) => p.isUnattributed).toList();

    return PunchPage(
      page: PaginatedResponse(items: rows, currentPage: 1, lastPage: 1, total: rows.length, perPage: perPage),
      unmatchedTotal: unmatchedTotal,
    );
  }

  @override
  Future<PunchUploadResult> uploadPunches({required String fileName, required List<int> bytes, int? schoolId}) async {
    if (failUploadWith != null) throw failUploadWith!;

    uploaded.add({'file_name': fileName, 'bytes': bytes.length, 'school_id': schoolId});

    return uploadResult;
  }
}

BiometricDevice fakeDevice({
  int id = 1,
  String name = 'Front gate',
  String serial = 'ZK-0001',
  String? location = 'Reception',
  String? lastSeenAt,
  bool hasPushKey = false,
}) {
  return BiometricDevice(
    id: id,
    schoolId: 1,
    schoolName: 'Abbey Road School',
    serialNumber: serial,
    name: name,
    location: location,
    status: 'active',
    lastSeenAt: lastSeenAt,
    hasPushKey: hasPushKey,
  );
}

BiometricPunch fakePunch({
  int id = 1,
  String biometricUserId = '17',
  int? staffProfileId = 5,
  String? staffName = 'Ada Ogun',
  String? employeeId = 'EMP-004',
  String? deviceName = 'Front gate',
  String source = 'device',
  String punchedAtLabel = '10/20/2026 09:02 AM',
  String localDate = '2026-10-20',
}) {
  return BiometricPunch(
    id: id,
    schoolId: 1,
    biometricUserId: biometricUserId,
    staffProfileId: staffProfileId,
    staffName: staffName,
    employeeId: employeeId,
    deviceName: deviceName,
    source: source,
    punchedAtLabel: punchedAtLabel,
    localDate: localDate,
  );
}

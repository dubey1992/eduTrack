import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/biometric/data/biometric_repository.dart';
import 'package:edutrack_app/features/biometric/data/models/biometric_device.dart';
import 'package:edutrack_app/features/biometric/presentation/device_list_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';

/// The fingerprint readers a school has (docs/biometric.md, B1).
///
/// A registry. The one thing it has to get right beyond listing rows is the
/// difference between a device **registered and never heard from** - which
/// is somebody's next job - and one that spoke and then stopped, which is a
/// fault. A blank in that column would read as neither.
class FakeBiometricRepository implements BiometricRepository {
  FakeBiometricRepository({List<BiometricDevice>? devices}) : _devices = devices ?? [];

  List<BiometricDevice> _devices;

  String? lastQuery;
  int? lastSchoolFilter;
  Failure? failListWith;
  final List<Map<String, Object?>> created = [];
  final List<int> removed = [];

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
  }) async {
    created.add({'school_id': schoolId, 'name': name, 'serial_number': serialNumber, 'location': location});

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
  Future<BiometricDevice> updateDevice(int deviceId, {String? name, String? serialNumber, String? location}) async {
    return _devices.firstWhere((d) => d.id == deviceId);
  }

  @override
  Future<void> deleteDevice(int deviceId) async {
    removed.add(deviceId);
    _devices = _devices.where((d) => d.id != deviceId).toList();
  }
}

BiometricDevice _device({
  int id = 1,
  String name = 'Front gate',
  String serial = 'ZK-0001',
  String? location = 'Reception',
  String? lastSeenAt,
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
  );
}

const _admin = AuthenticatedUser(id: 1, name: 'Admin', email: 'admin@example.com', role: UserRole.schoolAdmin);

Widget wrap(FakeBiometricRepository fake, {AuthenticatedUser actor = _admin}) {
  return ProviderScope(
    overrides: [
      biometricRepositoryProvider.overrideWithValue(fake),
      authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: actor)),
    ],
    child: MaterialApp(
      theme: AppTheme.light(),
      home: const Scaffold(body: DeviceListScreen()),
    ),
  );
}

void useDesktop(WidgetTester tester) {
  tester.view.physicalSize = const Size(1500, 1200);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('it lists the devices a school has', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [_device()])));
    await tester.pumpAndSettle();

    expect(find.text('Front gate'), findsOneWidget);
    expect(find.text('ZK-0001'), findsOneWidget);
    expect(find.text('Reception'), findsOneWidget);
  });

  testWidgets('no devices yet says so', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(wrap(FakeBiometricRepository()));
    await tester.pumpAndSettle();

    expect(find.text('No devices registered yet.'), findsOneWidget);
  });

  group('whether a device has ever spoken', () {
    testWidgets('one never heard from says exactly that', (tester) async {
      // Not a blank: a blank reads as "no information", and this is
      // information - it is somebody's next job.
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [_device()])));
      await tester.pumpAndSettle();

      expect(find.text('Never heard from'), findsOneWidget);
    });

    testWidgets('one that has spoken shows when', (tester) async {
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [_device(lastSeenAt: '2026-10-20T06:30:00Z')])));
      await tester.pumpAndSettle();

      expect(find.text('Never heard from'), findsNothing);
      expect(find.textContaining('10/20/2026'), findsOneWidget);
    });
  });

  testWidgets('searching asks the server', (tester) async {
    useDesktop(tester);
    final fake = FakeBiometricRepository(
      devices: [
        _device(),
        _device(id: 2, name: 'Staff room', serial: 'ZK-0002'),
      ],
    );
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextField, 'Search devices'), 'staff');
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();

    expect(fake.lastQuery, 'staff');
    expect(find.text('Staff room'), findsOneWidget);
    expect(find.text('Front gate'), findsNothing);
  });

  testWidgets('a failure shows its message with a retry', (tester) async {
    useDesktop(tester);
    final fake = FakeBiometricRepository()..failListWith = Failure.network();
    await tester.pumpWidget(wrap(fake));
    await tester.pumpAndSettle();

    expect(find.textContaining('Could not reach the server'), findsOneWidget);
    expect(find.widgetWithText(OutlinedButton, 'Retry'), findsOneWidget);
  });

  group('removing one', () {
    testWidgets('asks first, and says what it does not do', (tester) async {
      // Removing it from the register does not change the device itself,
      // and somebody about to press it should know that.
      useDesktop(tester);
      await tester.pumpWidget(wrap(FakeBiometricRepository(devices: [_device()])));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();

      expect(find.text('Remove device?'), findsOneWidget);
      expect(find.textContaining('The device itself is not changed'), findsOneWidget);
    });

    testWidgets('cancelling leaves it alone', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository(devices: [_device()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.pumpAndSettle();

      expect(fake.removed, isEmpty);
      expect(find.text('Front gate'), findsOneWidget);
    });

    testWidgets('confirming removes it', (tester) async {
      useDesktop(tester);
      final fake = FakeBiometricRepository(devices: [_device()]);
      await tester.pumpWidget(wrap(fake));
      await tester.pumpAndSettle();

      await tester.tap(find.byTooltip('Remove'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Remove'));
      await tester.pumpAndSettle();

      expect(fake.removed, [1]);
    });
  });

  testWidgets('somebody who may not manage the register sees no controls', (tester) async {
    useDesktop(tester);
    await tester.pumpWidget(
      wrap(
        FakeBiometricRepository(devices: [_device()]),
        actor: const AuthenticatedUser(id: 2, name: 'Teacher', email: 'teacher@example.com', role: UserRole.teacher),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Front gate'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'Register Device'), findsNothing);
    expect(find.byTooltip('Remove'), findsNothing);
  });
}

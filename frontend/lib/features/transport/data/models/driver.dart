import 'transport_status.dart';

class Driver {
  const Driver({
    required this.id,
    required this.schoolId,
    required this.schoolName,
    required this.name,
    required this.mobile,
    required this.licenceNumber,
    required this.licenceExpiry,
    required this.status,
    required this.routeId,
    required this.routeName,
  });

  factory Driver.fromJson(Map<String, dynamic> json) {
    return Driver(
      id: json['id'] as int,
      schoolId: json['school_id'] as int,
      schoolName: json['school_name'] as String?,
      name: json['name'] as String,
      mobile: json['mobile'] as String?,
      licenceNumber: json['licence_number'] as String,
      licenceExpiry: json['licence_expiry'] as String?,
      status: TransportStatus.fromApiValue(json['status'] as String),
      routeId: json['route_id'] as int?,
      routeName: json['route_name'] as String?,
    );
  }

  final int id;
  final int schoolId;
  final String? schoolName;
  final String name;
  final String? mobile;
  final String licenceNumber;

  /// `yyyy-MM-dd`, or null when not recorded.
  final String? licenceExpiry;
  final TransportStatus status;
  final int? routeId;
  final String? routeName;

  bool get isActive => status == TransportStatus.active;

  bool get isLicenceExpired {
    final expiry = licenceExpiry;
    if (expiry == null) return false;
    final today = DateTime.now();
    return DateTime.parse(expiry).isBefore(DateTime(today.year, today.month, today.day));
  }
}

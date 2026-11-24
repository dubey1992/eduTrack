import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';

/// Where a request stands.
enum GuardianInviteStatus {
  pending('pending', 'Waiting'),
  approved('approved', 'Approved'),
  declined('declined', 'Declined');

  const GuardianInviteStatus(this.apiValue, this.label);

  final String apiValue;
  final String label;

  static GuardianInviteStatus fromApiValue(String? value) =>
      values.where((status) => status.apiValue == value).firstOrNull ?? pending;
}

/// A parent asking the school to add another guardian of their child, as the
/// office sees it (docs/mobile-apps-review.md, M8, 8.5).
class GuardianInvite {
  const GuardianInvite({
    required this.id,
    required this.name,
    required this.mobile,
    required this.relationship,
    required this.status,
    required this.studentId,
    required this.studentName,
    required this.admissionNumber,
    required this.classSectionName,
    required this.requestedByName,
    this.askedAt,
    this.decidedByName,
  });

  factory GuardianInvite.fromJson(Map<String, dynamic> json) => GuardianInvite(
    id: json['id'] as int,
    name: json['name'] as String,
    mobile: json['mobile'] as String,
    relationship: json['relationship'] as String,
    status: GuardianInviteStatus.fromApiValue(json['status'] as String?),
    studentId: json['student_id'] as int,
    studentName: json['student_name'] as String,
    admissionNumber: json['admission_number'] as String,
    classSectionName: json['class_section_name'] as String?,
    requestedByName: json['requested_by_name'] as String,
    askedAt: json['asked_at'] == null ? null : DateTime.parse(json['asked_at'] as String).toLocal(),
    decidedByName: json['decided_by_name'] as String?,
  );

  final int id;
  final String name;
  final String mobile;
  final String relationship;
  final GuardianInviteStatus status;
  final int studentId;
  final String studentName;
  final String admissionNumber;
  final String? classSectionName;

  /// The parent who asked.
  final String requestedByName;
  final DateTime? askedAt;
  final String? decidedByName;
}

final guardianInvitesRepositoryProvider = Provider<GuardianInvitesRepository>(
  (ref) => GuardianInvitesRepository(ref.watch(dioClientProvider)),
);

/// guardian-invites on the API (school/views/guardian_invites.py).
class GuardianInvitesRepository {
  GuardianInvitesRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<GuardianInvite>> list({required GuardianInviteStatus status, int page = 1}) => _call(
    () async {
      final response = await _dio.get('/guardian-invites', queryParameters: {'status': status.apiValue, 'page': page});
      return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, GuardianInvite.fromJson);
    },
  );

  Future<GuardianInvite> approve(int inviteId) => _call(() async {
    final response = await _dio.post('/guardian-invites/$inviteId/approve');
    return GuardianInvite.fromJson((response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
  });

  Future<GuardianInvite> decline(int inviteId) => _call(() async {
    final response = await _dio.post('/guardian-invites/$inviteId/decline');
    return GuardianInvite.fromJson((response.data as Map<String, dynamic>)['data'] as Map<String, dynamic>);
  });
}

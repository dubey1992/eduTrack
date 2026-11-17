import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';

/// A parent's note that their child will be away, as the school sees it
/// (docs/parent-student-app.md, F5). It never marks the register; whoever
/// keeps the register acknowledges it, and the parent sees that.
class StaffAbsenceNote {
  const StaffAbsenceNote({
    required this.id,
    required this.studentId,
    required this.studentName,
    required this.startDate,
    required this.endDate,
    required this.reason,
    required this.hasPhoto,
    required this.acknowledged,
    required this.sentBy,
    this.acknowledgedBy,
  });

  factory StaffAbsenceNote.fromJson(Map<String, dynamic> json) {
    final student = json['student'] as Map<String, dynamic>;
    return StaffAbsenceNote(
      id: json['id'] as int,
      studentId: student['id'] as int,
      studentName: student['name'] as String,
      startDate: DateTime.parse(json['start_date'] as String),
      endDate: DateTime.parse(json['end_date'] as String),
      reason: json['reason'] as String,
      hasPhoto: json['has_photo'] as bool,
      acknowledged: json['status'] == 'acknowledged',
      sentBy: json['sent_by'] as String,
      acknowledgedBy: json['acknowledged_by'] as String?,
    );
  }

  final int id;
  final int studentId;
  final String studentName;
  final DateTime startDate;
  final DateTime endDate;
  final String reason;
  final bool hasPhoto;
  final bool acknowledged;

  /// The parent who sent it.
  final String sentBy;
  final String? acknowledgedBy;
}

/// The note a register row carries for its day: enough to show and to
/// acknowledge it without another request.
class RegisterAbsenceNote {
  const RegisterAbsenceNote({
    required this.id,
    required this.reason,
    required this.acknowledged,
    required this.hasPhoto,
  });

  static RegisterAbsenceNote? fromJson(Map<String, dynamic>? json) => json == null
      ? null
      : RegisterAbsenceNote(
          id: json['id'] as int,
          reason: json['reason'] as String,
          acknowledged: json['status'] == 'acknowledged',
          hasPhoto: json['has_photo'] as bool? ?? false,
        );

  final int id;
  final String reason;
  final bool acknowledged;
  final bool hasPhoto;
}

final absenceNotesRepositoryProvider = Provider<AbsenceNotesRepository>(
  (ref) => AbsenceNotesRepository(ref.watch(dioClientProvider)),
);

/// absence-notes on the API (school/views/absence_notes.py).
class AbsenceNotesRepository {
  AbsenceNotesRepository(this._dio);

  final Dio _dio;

  Future<T> _call<T>(Future<T> Function() request) async {
    try {
      return await request();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  /// [unseenOnly] true lists the notes nobody has acknowledged yet.
  Future<PaginatedResponse<StaffAbsenceNote>> list({bool? unseenOnly, int page = 1}) => _call(() async {
    final response = await _dio.get(
      '/absence-notes',
      queryParameters: {'page': page, if (unseenOnly != null) 'status': unseenOnly ? 'sent' : 'acknowledged'},
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, StaffAbsenceNote.fromJson);
  });

  Future<StaffAbsenceNote> acknowledge(int noteId) => _call(() async {
    final response = await _dio.post('/absence-notes/$noteId/acknowledge');
    return StaffAbsenceNote.fromJson(response.data as Map<String, dynamic>);
  });

  /// The doctor's note, as image bytes.
  Future<List<int>> photo(int noteId) => _call(() async {
    final response = await _dio.get<List<int>>(
      '/absence-notes/$noteId/photo',
      options: Options(responseType: ResponseType.bytes),
    );
    return response.data ?? const [];
  });
}

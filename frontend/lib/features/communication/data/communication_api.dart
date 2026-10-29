import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'models/message.dart';

final communicationApiProvider = Provider<CommunicationApi>((ref) => CommunicationApi(ref.watch(dioClientProvider)));

class CommunicationApi {
  CommunicationApi(this._dio);

  final Dio _dio;

  Future<PaginatedResponse<Message>> listMessages({
    int? schoolId,
    MessageCategory? category,
    MessageChannel? channel,
    MessageStatus? status,
    String? dateFrom,
    String? dateTo,
    String? search,
    int? page,
    int? perPage,
  }) async {
    final response = await _dio.get(
      '/communication/messages',
      queryParameters: {
        'school_id': ?schoolId,
        'category': ?category?.apiValue,
        'channel': ?channel?.apiValue,
        'status': ?status?.apiValue,
        'date_from': ?dateFrom,
        'date_to': ?dateTo,
        'q': ?search,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Message.fromJson);
  }

  Future<MessageSummary> summary({int? schoolId, MessageCategory? category}) async {
    final response = await _dio.get(
      '/communication/summary',
      queryParameters: {'school_id': ?schoolId, 'category': ?category?.apiValue},
    );
    return MessageSummary.fromJson(response.data as Map<String, dynamic>);
  }

  Future<Message> retry(int messageId) async {
    final response = await _dio.post('/communication/messages/$messageId/retry');
    return Message.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<MessageTemplate>> listTemplates({int? schoolId}) async {
    final response = await _dio.get('/communication/templates', queryParameters: {'school_id': ?schoolId});
    return (response.data as List<dynamic>)
        .map((value) => MessageTemplate.fromJson(value as Map<String, dynamic>))
        .toList(growable: false);
  }

  Future<MessageTemplate> updateTemplate(String event, {int? schoolId, required String body}) async {
    final response = await _dio.put('/communication/templates/$event', data: {'school_id': ?schoolId, 'body': body});
    return MessageTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  Future<MessageTemplate> resetTemplate(String event, {int? schoolId}) async {
    final response = await _dio.delete('/communication/templates/$event', queryParameters: {'school_id': ?schoolId});
    return MessageTemplate.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CommunicationSettings> settings({int? schoolId}) async {
    final response = await _dio.get('/communication/settings', queryParameters: {'school_id': ?schoolId});
    return CommunicationSettings.fromJson(response.data as Map<String, dynamic>);
  }

  Future<CommunicationSettings> updateSettings({
    int? schoolId,
    required bool smsEnabled,
    required AttendanceAlertMode attendanceAlerts,
    required bool transportAlertsEnabled,
    required bool leaveAlertsEnabled,
    bool? resultAlertsEnabled,
    bool? whatsappEnabled,
    bool? emailEnabled,
  }) async {
    final response = await _dio.put(
      '/communication/settings',
      data: {
        'school_id': ?schoolId,
        'sms_enabled': smsEnabled,
        'attendance_alerts': attendanceAlerts.apiValue,
        'transport_alerts_enabled': transportAlertsEnabled,
        'leave_alerts_enabled': leaveAlertsEnabled,
        'result_alerts_enabled': ?resultAlertsEnabled,
        'whatsapp_enabled': ?whatsappEnabled,
        'email_enabled': ?emailEnabled,
      },
    );
    return CommunicationSettings.fromJson(response.data as Map<String, dynamic>);
  }

  /// One message through School365ai's account, now. Returns the
  /// server's confirmation sentence.
  Future<String> testGateway({int? schoolId, required MessageChannel channel, required String to}) async {
    final response = await _dio.post(
      '/communication/settings/test',
      data: {'school_id': ?schoolId, 'channel': channel.apiValue, 'to': to},
    );
    return (response.data as Map<String, dynamic>)['message'] as String? ?? 'A test message was sent.';
  }

  Future<NoticeResult> previewNotice({
    int? schoolId,
    required NoticeKind kind,
    required NoticeAudience audienceType,
    int? audienceId,
    NoticeRecipients? recipients,
    required List<MessageChannel> channels,
  }) async {
    final response = await _dio.get(
      '/communication/notices/preview',
      queryParameters: {
        'school_id': ?schoolId,
        'kind': kind.apiValue,
        'audience_type': audienceType.apiValue,
        'audience_id': ?audienceId,
        'recipients': ?recipients?.apiValue,
        'channels': MessageChannel.joined(channels),
      },
    );
    return NoticeResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<NoticeResult> sendNotice({
    int? schoolId,
    required NoticeKind kind,
    required NoticeAudience audienceType,
    int? audienceId,
    NoticeRecipients? recipients,
    required List<MessageChannel> channels,
    String? subject,
    String? body,
    String? amount,
    String? dueDate,
  }) async {
    final response = await _dio.post(
      '/communication/notices',
      data: {
        'school_id': ?schoolId,
        'kind': kind.apiValue,
        'audience_type': audienceType.apiValue,
        'audience_id': ?audienceId,
        'recipients': ?recipients?.apiValue,
        'channels': [for (final channel in channels) channel.apiValue],
        'subject': ?subject,
        'body': ?body,
        'amount': ?amount,
        'due_date': ?dueDate,
      },
    );
    return NoticeResult.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PaginatedResponse<Message>> inbox({
    bool unreadOnly = false,
    int? page,
    int? perPage,
    String? dateFrom,
    String? dateTo,
  }) async {
    final response = await _dio.get(
      '/inbox',
      queryParameters: {
        'unread': ?(unreadOnly ? 1 : null),
        'date_from': ?dateFrom,
        'date_to': ?dateTo,
        'page': ?page,
        'per_page': ?perPage,
      },
    );
    return PaginatedResponse.fromJson(response.data as Map<String, dynamic>, Message.fromJson);
  }

  Future<int> unreadCount() async {
    final response = await _dio.get('/inbox/unread-count');
    return (response.data as Map<String, dynamic>)['unread'] as int? ?? 0;
  }

  Future<Message> markRead(int messageId) async {
    final response = await _dio.post('/inbox/$messageId/read');
    return Message.fromJson(response.data as Map<String, dynamic>);
  }

  Future<int> markAllRead() async {
    final response = await _dio.post('/inbox/read-all');
    return (response.data as Map<String, dynamic>)['marked'] as int? ?? 0;
  }
}

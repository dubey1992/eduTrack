import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../core/network/paginated_response.dart';
import 'communication_api.dart';
import 'models/message.dart';

final communicationRepositoryProvider = Provider<CommunicationRepository>(
  (ref) => CommunicationRepository(ref.watch(communicationApiProvider)),
);

/// Turns Dio errors into the app's Failure, exactly like the other
/// repositories, so the screens only ever see one error type.
class CommunicationRepository {
  CommunicationRepository(this._api);

  final CommunicationApi _api;

  Future<T> _guard<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on DioException catch (e) {
      throw failureFromDioException(e);
    }
  }

  Future<PaginatedResponse<Message>> listMessages({
    int? schoolId,
    MessageCategory? category,
    MessageChannel? channel,
    MessageStatus? status,
    String? dateFrom,
    String? dateTo,
    String? search,
    required int page,
    required int perPage,
  }) {
    return _guard(
      () => _api.listMessages(
        schoolId: schoolId,
        category: category,
        channel: channel,
        status: status,
        dateFrom: dateFrom,
        dateTo: dateTo,
        search: search,
        page: page,
        perPage: perPage,
      ),
    );
  }

  Future<MessageSummary> summary({int? schoolId, MessageCategory? category}) {
    return _guard(() => _api.summary(schoolId: schoolId, category: category));
  }

  Future<Message> retry(int messageId) => _guard(() => _api.retry(messageId));

  Future<List<MessageTemplate>> listTemplates({int? schoolId}) {
    return _guard(() => _api.listTemplates(schoolId: schoolId));
  }

  Future<MessageTemplate> updateTemplate(String event, {int? schoolId, required String body}) {
    return _guard(() => _api.updateTemplate(event, schoolId: schoolId, body: body));
  }

  Future<MessageTemplate> resetTemplate(String event, {int? schoolId}) {
    return _guard(() => _api.resetTemplate(event, schoolId: schoolId));
  }

  Future<MessageTemplate> setWhatsappTemplate(
    String event, {
    int? schoolId,
    required String templateName,
    required String language,
    required List<String> parameters,
  }) {
    return _guard(
      () => _api.setWhatsappTemplate(
        event,
        schoolId: schoolId,
        templateName: templateName,
        language: language,
        parameters: parameters,
      ),
    );
  }

  Future<MessageTemplate> clearWhatsappTemplate(String event, {int? schoolId}) {
    return _guard(() => _api.clearWhatsappTemplate(event, schoolId: schoolId));
  }

  Future<CommunicationSettings> settings({int? schoolId}) => _guard(() => _api.settings(schoolId: schoolId));

  Future<CommunicationSettings> updateSettings({
    int? schoolId,
    required bool smsEnabled,
    required AttendanceAlertMode attendanceAlerts,
    required bool transportAlertsEnabled,
    required bool leaveAlertsEnabled,
    required String provider,
    String? senderId,
    bool? whatsappEnabled,
    String? whatsappProvider,
    bool? emailEnabled,
    Map<String, Map<String, String>>? credentials,
  }) {
    return _guard(
      () => _api.updateSettings(
        schoolId: schoolId,
        smsEnabled: smsEnabled,
        attendanceAlerts: attendanceAlerts,
        transportAlertsEnabled: transportAlertsEnabled,
        leaveAlertsEnabled: leaveAlertsEnabled,
        provider: provider,
        senderId: senderId,
        whatsappEnabled: whatsappEnabled,
        whatsappProvider: whatsappProvider,
        emailEnabled: emailEnabled,
        credentials: credentials,
      ),
    );
  }

  Future<String> testGateway({int? schoolId, required MessageChannel channel, required String to}) {
    return _guard(() => _api.testGateway(schoolId: schoolId, channel: channel, to: to));
  }

  Future<NoticeResult> previewNotice({
    int? schoolId,
    required NoticeKind kind,
    required NoticeAudience audienceType,
    int? audienceId,
    NoticeRecipients? recipients,
    required List<MessageChannel> channels,
  }) {
    return _guard(
      () => _api.previewNotice(
        schoolId: schoolId,
        kind: kind,
        audienceType: audienceType,
        audienceId: audienceId,
        recipients: recipients,
        channels: channels,
      ),
    );
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
  }) {
    return _guard(
      () => _api.sendNotice(
        schoolId: schoolId,
        kind: kind,
        audienceType: audienceType,
        audienceId: audienceId,
        recipients: recipients,
        channels: channels,
        subject: subject,
        body: body,
        amount: amount,
        dueDate: dueDate,
      ),
    );
  }

  Future<PaginatedResponse<Message>> inbox({bool unreadOnly = false, required int page, required int perPage}) {
    return _guard(() => _api.inbox(unreadOnly: unreadOnly, page: page, perPage: perPage));
  }

  Future<int> unreadCount() => _guard(_api.unreadCount);

  Future<Message> markRead(int messageId) => _guard(() => _api.markRead(messageId));

  Future<int> markAllRead() => _guard(_api.markAllRead);
}

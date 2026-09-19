import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/communication_repository.dart';
import '../data/models/message.dart';

/// Every event's wording for one school. The school id is the family key so
/// a Super Admin switching schools reloads rather than showing stale text.
final templateNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<TemplateNotifier, List<MessageTemplate>, int?>(TemplateNotifier.new);

class TemplateNotifier extends AsyncNotifier<List<MessageTemplate>> {
  TemplateNotifier(this.schoolId);

  final int? schoolId;

  @override
  Future<List<MessageTemplate>> build() {
    return ref.read(communicationRepositoryProvider).listTemplates(schoolId: schoolId);
  }

  Future<void> save(String event, String body) async {
    await ref.read(communicationRepositoryProvider).updateTemplate(event, schoolId: schoolId, body: body);
    await _reload();
  }

  /// Drops the school's override so the event goes back to its shipped wording.
  Future<void> resetToDefault(String event) async {
    await ref.read(communicationRepositoryProvider).resetTemplate(event, schoolId: schoolId);
    await _reload();
  }

  /// Maps the event to one of the school's approved WhatsApp templates;
  /// [parameters] are token names in the order they fill {{1}}, {{2}}, ...
  Future<void> saveWhatsapp(
    String event, {
    required String templateName,
    required String language,
    required List<String> parameters,
  }) async {
    await ref
        .read(communicationRepositoryProvider)
        .setWhatsappTemplate(
          event,
          schoolId: schoolId,
          templateName: templateName,
          language: language,
          parameters: parameters,
        );
    await _reload();
  }

  Future<void> clearWhatsapp(String event) async {
    await ref.read(communicationRepositoryProvider).clearWhatsappTemplate(event, schoolId: schoolId);
    await _reload();
  }

  Future<void> _reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(communicationRepositoryProvider).listTemplates(schoolId: schoolId));
  }
}

/// A school's alert switches, channels and provider accounts.
final communicationSettingsNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<CommunicationSettingsNotifier, CommunicationSettings, int?>(CommunicationSettingsNotifier.new);

class CommunicationSettingsNotifier extends AsyncNotifier<CommunicationSettings> {
  CommunicationSettingsNotifier(this.schoolId);

  final int? schoolId;

  @override
  Future<CommunicationSettings> build() {
    return ref.read(communicationRepositoryProvider).settings(schoolId: schoolId);
  }

  /// [credentials] carries only what the administrator typed or cleared:
  /// {provider: {key: value}}, with "" meaning "clear". Anything left out
  /// stays as it is on the server, so a saved secret never has to be re-entered.
  Future<void> save({
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
  }) async {
    final saved = await ref
        .read(communicationRepositoryProvider)
        .updateSettings(
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
        );

    state = AsyncData(saved);
  }

  /// One message through the school's saved provider, now. Returns the
  /// server's confirmation; a refusal surfaces as a Failure.
  Future<String> sendTest({required MessageChannel channel, required String to}) {
    return ref.read(communicationRepositoryProvider).testGateway(schoolId: schoolId, channel: channel, to: to);
  }
}

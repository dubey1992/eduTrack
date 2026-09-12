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

  Future<void> _reload() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(communicationRepositoryProvider).listTemplates(schoolId: schoolId));
  }
}

/// A school's alert switches.
final communicationSettingsNotifierProvider = AsyncNotifierProvider.autoDispose
    .family<CommunicationSettingsNotifier, CommunicationSettings, int?>(CommunicationSettingsNotifier.new);

class CommunicationSettingsNotifier extends AsyncNotifier<CommunicationSettings> {
  CommunicationSettingsNotifier(this.schoolId);

  final int? schoolId;

  @override
  Future<CommunicationSettings> build() {
    return ref.read(communicationRepositoryProvider).settings(schoolId: schoolId);
  }

  Future<void> save({
    required bool smsEnabled,
    required AttendanceAlertMode attendanceAlerts,
    required bool transportAlertsEnabled,
    required bool leaveAlertsEnabled,
    required String provider,
    String? senderId,
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
        );

    state = AsyncData(saved);
  }
}

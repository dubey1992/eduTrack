import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/models/user_role.dart';
import '../../auth/application/auth_notifier.dart';
import '../../auth/data/models/authenticated_user.dart';
import '../../setup_guide/application/setup_guide_notifier.dart';
import '../data/school_logo_repository.dart';

/// The largest logo the server keeps, checked here first so a too-big file
/// is not uploaded only to be turned away.
const maxLogoBytes = 2 * 1024 * 1024;
const _logoExtensions = ['.png', '.jpg', '.jpeg'];

/// What is wrong with a chosen file before it is sent, or null when nothing is.
String? logoProblem({required String fileName, required int length}) {
  final name = fileName.toLowerCase();
  if (!_logoExtensions.any(name.endsWith)) return 'The logo must be a JPEG or PNG image.';
  if (length > maxLogoBytes) return 'The logo must be 2 MB or smaller.';
  return null;
}

/// Whether the signed-in School Admin should be asked for the school's logo:
/// every sign-in, until the school has one (decided 2026-11-17).
bool needsLogoPrompt(AuthenticatedUser? user) =>
    user != null && user.role == UserRole.schoolAdmin && !user.schoolProfileComplete;

/// Whether this session has already asked. Reset at sign-out, so the next
/// sign-in asks again; a reload of the web app counts as opening it afresh.
final logoPromptShownProvider = NotifierProvider<LogoPromptShown, bool>(LogoPromptShown.new);

class LogoPromptShown extends Notifier<bool> {
  @override
  bool build() => false;

  void markShown() => state = true;
}

final schoolLogoControllerProvider = Provider<SchoolLogoController>(SchoolLogoController.new);

/// Uploads or removes a school's logo, then brings the session up to date so
/// the menu shows the new logo and the reminder goes away.
class SchoolLogoController {
  SchoolLogoController(this._ref);

  final Ref _ref;

  Future<SchoolLogoResult> upload({required int schoolId, required List<int> bytes, required String fileName}) async {
    final result = await _ref
        .read(schoolLogoRepositoryProvider)
        .upload(schoolId: schoolId, bytes: bytes, fileName: fileName);
    await _changed(schoolId);
    return result;
  }

  Future<SchoolLogoResult> remove(int schoolId) async {
    final result = await _ref.read(schoolLogoRepositoryProvider).remove(schoolId);
    await _changed(schoolId);
    return result;
  }

  Future<void> _changed(int schoolId) async {
    final user = _ref.read(authNotifierProvider).value;
    if (user?.schoolId != schoolId) return;

    _ref.invalidate(setupGuideNotifierProvider);
    await _ref.read(authNotifierProvider.notifier).refreshSession();
  }
}

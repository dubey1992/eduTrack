import '../../../core/models/module_access.dart';
import '../../../core/models/user_role.dart';
import '../../auth/data/models/authenticated_user.dart';

/// Whether this person may set exams up, publish them and hold cards back:
/// the school's administrators, as the server's ExaminationPolicy says. A
/// Super Admin reads and changes nothing. The server decides regardless;
/// this only keeps buttons that would fail off the screen.
bool canManageExams(AuthenticatedUser? user) =>
    user != null &&
    user.role != UserRole.superAdmin &&
    user.role.administersSchool &&
    user.canView(AppModules.assessments);

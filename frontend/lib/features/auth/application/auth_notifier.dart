import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../setup_guide/application/setup_guide_notifier.dart';
import '../../analytics/application/analytics_notifier.dart';
import '../../../core/network/session_ended_notifier.dart';
import '../../academic_years/application/academic_year_list_notifier.dart';
import '../../assessments/application/assessment_list_notifier.dart';
import '../../platform_messaging/application/platform_messaging_notifier.dart';
import '../../promotion/application/promotion_history_notifier.dart';
import '../../promotion/application/promotion_notifier.dart';
import '../../grade_scales/application/grade_scale_notifier.dart';
import '../../announcements/application/announcement_page_notifier.dart';
import '../../audit/application/audit_log_notifier.dart';
import '../../company_details/application/company_details_notifier.dart';
import '../../mail_settings/application/mail_settings_notifier.dart';
import '../../maps/data/maps_config.dart';
import '../../schools/data/school_locations_repository.dart';
import '../../marketing/application/marketing_draft_notifier.dart';
import '../../my_register/application/register_queue.dart';
import '../../my_register/data/register_store.dart';
import '../../push/device_repository.dart';
import '../../my_trip/application/trip_mark_queue.dart';
import '../../classes/application/school_class_list_notifier.dart';
import '../../communication/application/inbox_notifier.dart';
import '../../communication/application/message_page_notifier.dart';
import '../../dashboard/application/dashboard_notifier.dart';
import '../../departments/application/department_list_notifier.dart';
import '../../demo_requests/application/demo_request_notifier.dart';
import '../../early_access/application/early_access_notifier.dart';
import '../../holidays/application/holiday_page_notifier.dart';
import '../../payments/application/payment_list_notifier.dart';
import '../../payments/application/payment_summary_notifier.dart';
import '../../permissions/application/permissions_notifier.dart';
import '../../profile/application/profile_notifier.dart';
import '../../transport/application/bus_stop_page_notifier.dart';
import '../../biometric/application/device_page_notifier.dart';
import '../../biometric/application/punch_page_notifier.dart';
import '../../schools/application/school_list_notifier.dart';
import '../../site_pages/application/site_page_notifiers.dart';
import '../../staff/application/staff_list_notifier.dart';
import '../../transport/application/crew_list_notifier.dart';
import '../../staff_leave/application/staff_leave_list_notifier.dart';
import '../../staff_leave/application/staff_leave_summary_notifier.dart';
import '../../students/application/student_list_notifier.dart';
import '../../subjects/application/subject_list_notifier.dart';
import '../../teaching_reports/application/teaching_report_summary_notifier.dart';
import '../../transport/application/driver_page_notifier.dart';
import '../../transport/application/route_page_notifier.dart';
import '../../transport/application/trip_history_notifier.dart';
import '../../transport/application/vehicle_page_notifier.dart';
import '../../users/application/user_list_notifier.dart';
import '../data/auth_repository.dart';
import 'reset_code_notifier.dart';
import '../data/models/authenticated_user.dart';

final authNotifierProvider = AsyncNotifierProvider<AuthNotifier, AuthenticatedUser?>(AuthNotifier.new);

/// Holds the current session. `null` data means "no one is logged in";
/// loading/error come for free from [AsyncValue] so the UI (via
/// [AsyncValueView]) shows the right state automatically.
class AuthNotifier extends AsyncNotifier<AuthenticatedUser?> {
  @override
  Future<AuthenticatedUser?> build() {
    ref.listen(sessionEndedProvider, (previous, ended) {
      if (ended && state.value != null) _sessionEnded();
    });

    return ref.read(authRepositoryProvider).restoreSession();
  }

  /// The server no longer accepts this session (see [sessionEndedProvider]):
  /// signed out on this device, back to the sign-in screen, which says why.
  /// Nothing is sent to the server, and nothing still waiting to be sent is
  /// thrown away - a bus phone's unsent marks and a teacher's unsent
  /// registers go when that person signs in again.
  Future<void> _sessionEnded() async {
    await ref.read(authRepositoryProvider).forgetSession();
    await _clearSavedClassLists();
    state = const AsyncData(null);
    _resetSessionScopedProviders();
  }

  /// Re-reads the session from /me - what the app gates on (module
  /// switches, permission levels) lives there, so a change made on a settings
  /// screen shows in the sidebar at once rather than at the next sign-in.
  Future<void> refreshSession() async {
    if (!state.hasValue || state.value == null) return;

    final refreshed = await ref.read(authRepositoryProvider).restoreSession();
    if (refreshed != null) state = AsyncData(refreshed);
  }

  Future<void> login({required String email, required String password}) async {
    // Deliberately no `state = const AsyncLoading()` here: the router's
    // redirect treats authNotifierProvider.isLoading as "show the splash
    // screen", which is right for the initial session restore in build()
    // but would bounce LoginScreen through /splash and back on every login
    // attempt - tearing it down mid-flight and losing the error listener
    // before a failed login's error ever reaches it. LoginScreen already
    // tracks its own submitting state locally for the button spinner.
    state = await AsyncValue.guard(() => ref.read(authRepositoryProvider).login(email: email, password: password));
    // Guards against the same browser tab going straight from one signed-in
    // session to another (e.g. testing a School Admin account right after a
    // Super Admin one) without an intervening full reload - without this,
    // every list screen below kept whatever it had already fetched for the
    // PREVIOUS user, since none of these providers are autoDispose or
    // otherwise tied to the session. That looked exactly like a school-data
    // isolation bug even though the API itself was scoping correctly.
    if (state.hasValue) {
      ref.read(sessionEndedProvider.notifier).clear();
      _resetSessionScopedProviders();
    }
  }

  /// Takes a session that was opened some other way than [login] - a bus
  /// attendant's passcode sign-in, whose token the attendant repository has
  /// already stored.
  void signedIn(AuthenticatedUser user) {
    ref.read(sessionEndedProvider.notifier).clear();
    state = AsyncData(user);
    _resetSessionScopedProviders();
  }

  /// Changes the signed-in user's password and refreshes the session, so a
  /// user who was being held on the change-password screen is let through
  /// the moment it succeeds.
  Future<void> changePassword({required String currentPassword, required String password}) async {
    final user = await ref
        .read(authRepositoryProvider)
        .changePassword(currentPassword: currentPassword, password: password);

    state = AsyncData(user);
  }

  Future<void> logout() async {
    // A bus attendant's phone keeps trip marks and the trip itself for when
    // there is no signal; none of it is for whoever signs in next. (Unsent
    // marks were warned about before getting here - see AppShell.)
    if (state.value?.role.isCrew ?? false) {
      await ref.read(tripMarkQueueProvider.notifier).discardAll();
    }
    await _clearSavedClassLists();
    // Taken back while still signed in - the server needs to know whose it
    // was. Never blocks signing out (features/push).
    await ref.read(pushRegistrationProvider).forget();
    await ref.read(authRepositoryProvider).logout();
    state = const AsyncData(null);
    _resetSessionScopedProviders();
  }

  /// A teacher's saved class lists name children, so they go with the
  /// session. Never blocks signing out - a phone whose store fails still
  /// signs out.
  Future<void> _clearSavedClassLists() async {
    try {
      await ref.read(registerStoreProvider).clearRosters();
    } catch (error) {
      debugPrint('Saved class lists could not be cleared on sign-out: $error');
    }
  }

  /// Every top-level list/summary provider that caches data fetched under
  /// the previous session. New feature list providers need to be added here
  /// too, or they'll leak the outgoing user's data into the next session.
  void _resetSessionScopedProviders() {
    // Registers waiting for signal stay saved on the phone for the teacher
    // who took them, and go when they next sign in; only the copy in
    // memory, and its retry timer, end with the session.
    ref.invalidate(registerQueueProvider);
    // A set-password code held from a link is no business of the next session.
    ref.invalidate(resetCodeProvider);
    ref.invalidate(schoolListNotifierProvider);
    // One school's setup progress, and whether it already opened itself
    // this session (docs/onboarding.md, O4).
    ref.invalidate(setupGuideNotifierProvider);
    ref.invalidate(setupGuideAutoOpenedProvider);
    ref.invalidate(userListNotifierProvider);
    ref.invalidate(studentListNotifierProvider);
    ref.invalidate(staffListNotifierProvider);
    ref.invalidate(crewListNotifierProvider);
    ref.invalidate(departmentListNotifierProvider);
    ref.invalidate(subjectListNotifierProvider);
    ref.invalidate(schoolClassListNotifierProvider);
    ref.invalidate(academicYearListNotifierProvider);
    ref.invalidate(gradeScaleListNotifierProvider);
    ref.invalidate(assessmentListNotifierProvider);
    // A half-finished promotion belongs to the person who started it, and to
    // the school they were signed into.
    ref.invalidate(promotionNotifierProvider);
    ref.invalidate(promotionHistoryProvider);
    // The fingerprint readers one school has, which the next person to sign
    // in on this browser must not be shown (docs/biometric.md, B1).
    // The places one school's buses stop at, which are its own
    // (docs/maps.md).
    ref.invalidate(busStopPageNotifierProvider);
    ref.invalidate(devicePageNotifierProvider);
    // And what those readers recorded: one school's staff movements, with
    // names on them (docs/biometric.md, B2).
    ref.invalidate(punchPageNotifierProvider);
    ref.invalidate(paymentListNotifierProvider);
    ref.invalidate(paymentSummaryNotifierProvider);
    // Added in Phase 21, when a sweep found these still holding the previous
    // account's data - on a shared office computer, the next person would
    // briefly see the last person's leave, inbox, dashboard or audit trail.
    // auth_notifier_reset_test.dart now fails when a new one is missed.
    ref.invalidate(announcementPageNotifierProvider);
    ref.invalidate(auditLogNotifierProvider);
    ref.invalidate(mailSettingsNotifierProvider);
    ref.invalidate(platformMessagingNotifierProvider);
    ref.invalidate(companyDetailsNotifierProvider);
    ref.invalidate(marketingDraftNotifierProvider);
    ref.invalidate(sitePageListNotifierProvider);
    ref.invalidate(mapsConfigProvider);
    ref.invalidate(schoolLocationsProvider);
    ref.invalidate(dashboardNotifierProvider);
    // Analytics keeps its figures for the session (analytics_notifier.dart).
    ref.invalidate(analyticsMeasuresProvider);
    ref.invalidate(analyticsSeriesProvider);
    ref.invalidate(earlyWarningProvider);
    ref.invalidate(academicOverviewProvider);
    ref.invalidate(financeOverviewProvider);
    ref.invalidate(transportOverviewProvider);
    ref.invalidate(platformOverviewProvider);
    ref.invalidate(platformSchoolsProvider);
    ref.invalidate(departmentPageNotifierProvider);
    ref.invalidate(driverPageNotifierProvider);
    ref.invalidate(earlyAccessNotifierProvider);
    ref.invalidate(demoRequestNotifierProvider);
    ref.invalidate(holidayPageNotifierProvider);
    ref.invalidate(inboxNotifierProvider);
    ref.invalidate(messagePageNotifierProvider);
    // The permissions matrix is read on sign-in; a Super Admin who edits
    // it must not hand the previous session's copy to the next account.
    ref.invalidate(permissionsNotifierProvider);
    ref.invalidate(profileNotifierProvider);
    ref.invalidate(routePageNotifierProvider);
    ref.invalidate(schoolPageNotifierProvider);
    ref.invalidate(staffLeaveListNotifierProvider);
    ref.invalidate(staffLeaveSummaryNotifierProvider);
    ref.invalidate(teachingReportSummaryNotifierProvider);
    ref.invalidate(tripMarkQueueProvider);
    ref.invalidate(tripHistoryNotifierProvider);
    ref.invalidate(unreadCountProvider);
    ref.invalidate(vehiclePageNotifierProvider);
  }
}

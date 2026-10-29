import 'package:flutter/material.dart';

import '../../features/auth/data/models/authenticated_user.dart';
import '../models/module_access.dart';
import '../models/permission_level.dart';
import '../models/user_role.dart';

/// A single navigation destination: the sidebar entry, the page title/
/// subtitle shown in the topbar, and who is allowed to see it - all in one
/// place, so the visible menu and the route access control can never drift
/// apart (this is the router's only source of truth for access gating on
/// these routes; see AppRouter's redirect).
class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.allowedRoles,
    required this.pageTitle,
    required this.pageSubtitle,
    this.module,
    this.requiredLevel = PermissionLevel.view,
    this.deniedRoles = const {},
  });

  final String path;
  final String label;
  final IconData icon;

  /// The roles the screen was built for. For an item with no [module] this
  /// is the whole rule; for a module item it is the fallback when a session
  /// carries no permissions map (see [allows]).
  final Set<UserRole> allowedRoles;
  final String pageTitle;
  final String pageSubtitle;

  /// The module this screen belongs to (an [AppModules] key), when it is one
  /// the permissions matrix and the school's module switches govern. Null
  /// for the platform's own screens and administration, which stay role-gated.
  final String? module;

  /// The level the matrix must grant on [module] for the item to show.
  /// [PermissionLevel.none] means no level is asked of the matrix at all -
  /// only that the module is on, plus [allowedRoles] - for a screen that is
  /// everybody's own business, like My Payslips.
  final PermissionLevel requiredLevel;

  /// Roles kept out whatever the matrix grants them. A Bus Attendant manages
  /// transport, but only through My Trip: the fleet and trip screens are
  /// refused to them by the API (TransportMasterPolicy).
  final Set<UserRole> deniedRoles;

  /// Whether [user] may see this entry and open its route.
  ///
  /// A module item needs its module switched on for the user's school, and
  /// then the matrix decides: the user's level must reach [requiredLevel].
  /// A session that carries no matrix at all (an older payload, a role-only
  /// fixture) keeps the role set the screen was built with, so nothing
  /// changes for it.
  bool allows(AuthenticatedUser user) {
    if (deniedRoles.contains(user.role)) return false;

    final module = this.module;
    if (module == null) return allowedRoles.contains(user.role);

    if (!user.moduleOn(module)) return false;

    if (requiredLevel == PermissionLevel.none || !user.access.hasPermissions) {
      return allowedRoles.contains(user.role);
    }

    return user.level(module).atLeast(requiredLevel);
  }
}

class NavGroup {
  const NavGroup({required this.label, required this.items});

  final String label;
  final List<NavItem> items;
}

/// The app's navigation structure. Grows one group/item at a time as each
/// phase lands its screens - matches the prototype's grouped sidebar
/// (docs/prototype/school_management_prototype_v4_themes.html), just
/// sparser for now since most modules don't exist yet.
class AppNav {
  const AppNav._();

  static const _allRoles = {
    UserRole.superAdmin,
    UserRole.groupAdmin,
    UserRole.schoolAdmin,
    UserRole.hod,
    UserRole.teacher,
    UserRole.staff,
    UserRole.transportManager,
    UserRole.accountant,
  };

  /// Every role, the Bus Attendant included - for what is every signed-in
  /// person's own: the landing page and their inbox.
  static const _everyone = {..._allRoles, UserRole.busAttendant, UserRole.driver};

  static const overview = NavGroup(
    label: 'Overview',
    items: [
      NavItem(
        path: '/dashboard',
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        allowedRoles: _everyone,
        pageTitle: 'Dashboard',
        pageSubtitle: 'Daily school operations overview',
      ),
      NavItem(
        path: '/reports',
        module: AppModules.reports,
        label: 'Reports',
        icon: Icons.insights_outlined,
        // The roles ReportController lets through. A teacher sees their own
        // class on the attendance screen instead of a school-wide report; an
        // accountant reads staff attendance, which payroll is computed from.
        allowedRoles: {
          UserRole.superAdmin,
          UserRole.groupAdmin,
          UserRole.schoolAdmin,
          UserRole.hod,
          UserRole.transportManager,
          UserRole.accountant,
        },
        pageTitle: 'Reports',
        pageSubtitle: 'Attendance, teaching and transport over a period',
      ),
      NavItem(
        path: '/analytics',
        module: AppModules.reports,
        label: 'Analytics',
        icon: Icons.bar_chart_outlined,
        // Whoever reads the reports the charts come from (docs/analytics.md).
        allowedRoles: {
          UserRole.superAdmin,
          UserRole.groupAdmin,
          UserRole.schoolAdmin,
          UserRole.hod,
          UserRole.accountant,
          // Since A6: the route view (docs/analytics.md).
          UserRole.transportManager,
        },
        pageTitle: 'Analytics',
        pageSubtitle: 'How the figures move, week by week or month by month',
      ),
      NavItem(
        path: '/early-warning',
        module: AppModules.reports,
        label: 'Early Warning',
        icon: Icons.warning_amber_outlined,
        // Decided 2026-10-29 (docs/analytics.md, A3): admins see the school,
        // a class teacher their own class, a head of department the test
        // results in their subjects. A teacher's access is their class, not
        // the reports matrix, so only the Reports switch is asked of it.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod, UserRole.teacher},
        requiredLevel: PermissionLevel.none,
        pageTitle: 'Early Warning',
        pageSubtitle: 'Students whose attendance or results are low or falling',
      ),
    ],
  );

  static const administration = NavGroup(
    label: 'Administration',
    items: [
      NavItem(
        path: '/schools',
        label: 'Schools',
        icon: Icons.apartment_outlined,
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Schools',
        pageSubtitle: 'Onboard and manage schools on the platform',
      ),
      NavItem(
        path: '/early-access',
        label: 'Early Access',
        icon: Icons.mark_email_unread_outlined,
        // Schools asking to be let in - platform business, same as
        // onboarding and payments. See docs/early-access.md.
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Early Access Requests',
        pageSubtitle: 'Schools that have asked to join the platform',
      ),
      NavItem(
        path: '/demo-requests',
        label: 'Demo Requests',
        icon: Icons.event_available_outlined,
        // Schools asking to be shown the product - platform business, the
        // same as early access.
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Demo Requests',
        pageSubtitle: 'Schools that have asked for a demo',
      ),
      NavItem(
        path: '/payments',
        label: 'Payments',
        icon: Icons.payments_outlined,
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Payments',
        pageSubtitle: 'Payments received from schools',
      ),
      NavItem(
        path: '/users',
        label: 'Admin Users',
        icon: Icons.group_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin},
        pageTitle: 'Admin Users',
        pageSubtitle: 'School admin accounts and access',
      ),
      NavItem(
        path: '/audit-log',
        label: 'Audit Log',
        icon: Icons.history,
        // The roles the audit-log API lets through. A Super Admin reads every
        // school's trail and the platform's own; an admin reads their school's
        // (or their group's).
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin},
        pageTitle: 'Audit Log',
        pageSubtitle: 'Who changed what, and when',
      ),
      NavItem(
        path: '/module-settings',
        label: 'Module Settings',
        icon: Icons.tune,
        // A Super Admin grants a module to a school; a School Admin keeps it
        // on and tunes its settings. See docs/settings.md.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin},
        pageTitle: 'Module Settings',
        pageSubtitle: 'Which modules this school uses, and their settings',
      ),
      NavItem(
        path: '/permissions',
        label: 'Permissions',
        icon: Icons.admin_panel_settings_outlined,
        // The Super Admin edits the matrix; every administrator reads it.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin},
        pageTitle: 'Roles & Permissions',
        pageSubtitle: 'What each role may see and do',
      ),
      NavItem(
        path: '/homepage-content',
        label: 'Homepage Content',
        icon: Icons.web_outlined,
        // The words on the product's public front page, not any school's.
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Homepage Content',
        pageSubtitle: 'The words visitors read on the public homepage',
      ),
      NavItem(
        path: '/site-pages',
        label: 'Website Pages',
        icon: Icons.article_outlined,
        // About Us, the privacy policy, the terms - the product's, not a
        // school's (docs/site-pages.md).
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Website Pages',
        pageSubtitle: 'About, privacy, terms and other public pages',
      ),
      NavItem(
        path: '/company-details',
        label: 'Company Details',
        icon: Icons.business_outlined,
        // School365ai as a business - the issuer on its own receipts.
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Company Details',
        pageSubtitle: 'Who issues the receipts schools get for paying the platform',
      ),
      NavItem(
        path: '/mail-settings',
        label: 'Email Settings',
        icon: Icons.outgoing_mail,
        // The platform's own SMTP server, not any one school's.
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Email Settings',
        pageSubtitle: 'The SMTP server the platform sends through',
      ),
      NavItem(
        path: '/messaging-settings',
        label: 'Messaging',
        icon: Icons.sms_outlined,
        // School365ai's own Twilio account, which sends every school's SMS
        // and WhatsApp (docs/platform-messaging.md). Schools only switch
        // channels on or off.
        allowedRoles: {UserRole.superAdmin},
        pageTitle: 'Messaging',
        pageSubtitle: "SMS and WhatsApp for every school, through School365ai's Twilio account",
      ),
    ],
  );

  static const academics = NavGroup(
    label: 'Academics',
    items: [
      NavItem(
        path: '/academic-years',
        module: AppModules.academics,
        label: 'Academic Years',
        icon: Icons.calendar_today_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Academic Years',
        pageSubtitle: 'Academic year setup and rollover',
      ),
      NavItem(
        path: '/assessments',
        module: AppModules.assessments,
        label: 'Class Tests',
        icon: Icons.fact_check_outlined,
        // The roles the API lets in. A teacher sees the tests of the classes
        // the timetable gives them, an HOD their department's subjects - the
        // narrowing is the server's, not this menu's.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod, UserRole.teacher},
        pageTitle: 'Class Tests',
        pageSubtitle: 'Tests, assignments and quizzes',
      ),
      NavItem(
        path: '/grade-scales',
        module: AppModules.academics,
        label: 'Grade Scales',
        icon: Icons.workspace_premium_outlined,
        // Every role reads them: a teacher entering marks needs to know what
        // an 81 will be called. Only an administrator may write one, which
        // the screen and the API both enforce.
        allowedRoles: _allRoles,
        pageTitle: 'Grade Scales',
        pageSubtitle: 'How a percentage becomes a grade',
      ),
      NavItem(
        path: '/holidays',
        module: AppModules.academics,
        label: 'Holidays',
        icon: Icons.beach_access_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Holiday Calendar',
        pageSubtitle: 'School holidays and breaks that pause attendance, leave and teaching',
      ),
      NavItem(
        path: '/departments',
        module: AppModules.academics,
        label: 'Departments',
        icon: Icons.corporate_fare_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Departments',
        pageSubtitle: 'Academic departments and HOD assignment',
      ),
      NavItem(
        path: '/subjects',
        module: AppModules.academics,
        label: 'Subjects',
        icon: Icons.menu_book_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Subjects',
        pageSubtitle: 'Subject setup and lead teacher assignment',
      ),
      NavItem(
        path: '/classes',
        module: AppModules.academics,
        label: 'Classes & Sections',
        icon: Icons.school_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Classes & Sections',
        pageSubtitle: 'Class structure and teacher assignment',
      ),
      NavItem(
        path: '/promotion',
        module: AppModules.academics,
        // Deciding that a child repeats a year is staff work, so the API
        // refuses everyone else - including the Super Admin, who is not a
        // member of staff (docs/promotion.md).
        requiredLevel: PermissionLevel.manage,
        deniedRoles: {UserRole.superAdmin},
        label: 'Class Promotion',
        icon: Icons.move_up_outlined,
        allowedRoles: {UserRole.groupAdmin, UserRole.schoolAdmin},
        pageTitle: 'Class Promotion',
        pageSubtitle: 'Move a class into the next academic year',
      ),
      NavItem(
        path: '/timetable',
        module: AppModules.timetable,
        label: 'Timetable',
        icon: Icons.calendar_view_week_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Timetable',
        pageSubtitle: 'Class schedules and period management',
      ),
    ],
  );

  static const attendanceHr = NavGroup(
    label: 'Attendance & HR',
    items: [
      NavItem(
        path: '/attendance',
        module: AppModules.attendance,
        label: 'Student Attendance',
        icon: Icons.fact_check_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.teacher},
        pageTitle: 'Student Attendance',
        pageSubtitle: 'Daily class attendance register',
      ),
      NavItem(
        path: '/staff-attendance',
        module: AppModules.staffAttendance,
        label: 'Staff Attendance',
        icon: Icons.badge_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod},
        pageTitle: 'Staff Attendance',
        pageSubtitle: 'Daily teacher and staff attendance register',
      ),
      NavItem(
        path: '/biometric-devices',
        module: AppModules.biometric,
        label: 'Biometric Devices',
        icon: Icons.fingerprint,
        // Its own module, switched off until a school asks for it: a school
        // with no readers on the wall would find screens that can only ever
        // be empty. An HOD marks the staff register but does not buy the
        // hardware, which is why this is not the register's own row.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin},
        pageTitle: 'Biometric Devices',
        pageSubtitle: 'Fingerprint readers, and which staff are enrolled on them',
      ),
      NavItem(
        path: '/leaves',
        module: AppModules.leave,
        label: 'Staff Leave',
        icon: Icons.event_busy_outlined,
        allowedRoles: {
          UserRole.superAdmin,
          UserRole.groupAdmin,
          UserRole.schoolAdmin,
          UserRole.hod,
          UserRole.teacher,
          UserRole.staff,
          UserRole.transportManager,
          UserRole.accountant,
          UserRole.busAttendant,
          UserRole.driver,
        },
        pageTitle: 'Staff Leave',
        pageSubtitle: 'Leave requests, approvals and attendance sync',
      ),
      NavItem(
        path: '/teaching-reports',
        module: AppModules.teachingReports,
        label: 'Teaching Reports',
        icon: Icons.fact_check_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod, UserRole.teacher},
        pageTitle: 'Daily Teaching Reports',
        pageSubtitle: 'Scheduled periods, filed reports and HOD review',
      ),
      NavItem(
        path: '/syllabus',
        module: AppModules.syllabus,
        label: 'Syllabus',
        icon: Icons.menu_book_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod, UserRole.teacher},
        pageTitle: 'Syllabus Tracking',
        pageSubtitle: 'Curriculum outline and per-class coverage',
      ),
      NavItem(
        path: '/hod-reports',
        module: AppModules.hod,
        label: 'HOD Reports',
        icon: Icons.insights_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod},
        pageTitle: 'HOD / Staff Reports',
        pageSubtitle: 'Attendance and teaching performance by department',
      ),
      NavItem(
        path: '/payroll',
        module: AppModules.payroll,
        requiredLevel: PermissionLevel.manage,
        label: 'Payroll',
        icon: Icons.account_balance_wallet_outlined,
        // Run by an Accountant or an admin; a Super Admin reads it. See
        // docs/payroll.md - served by the Python backend only.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.accountant},
        pageTitle: 'Payroll',
        pageSubtitle: 'Salaries, monthly runs and payslips',
      ),
      NavItem(
        path: '/my-payslips',
        module: AppModules.payroll,
        requiredLevel: PermissionLevel.none,
        label: 'My Payslips',
        icon: Icons.receipt_long_outlined,
        // Everybody employed by a school - never the Super Admin, who is not.
        // Their own payslips, so no level on payroll is asked: it shows
        // whenever the school has payroll on.
        allowedRoles: {
          UserRole.groupAdmin,
          UserRole.schoolAdmin,
          UserRole.hod,
          UserRole.teacher,
          UserRole.staff,
          UserRole.transportManager,
          UserRole.accountant,
          UserRole.busAttendant,
          UserRole.driver,
        },
        pageTitle: 'My Payslips',
        pageSubtitle: 'Your finalized payslips',
      ),
    ],
  );

  static const people = NavGroup(
    label: 'People',
    items: [
      NavItem(
        path: '/staff',
        module: AppModules.staff,
        label: 'Teachers & Staff',
        icon: Icons.groups_2_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin},
        pageTitle: 'Teachers & Staff',
        pageSubtitle: 'Employee records, departments and assignments',
      ),
      NavItem(
        path: '/students',
        module: AppModules.students,
        label: 'Students',
        icon: Icons.school_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.teacher},
        pageTitle: 'Student Management',
        pageSubtitle: 'Admissions, profiles and class assignments',
      ),
    ],
  );

  static const _transportViewerRoles = {
    UserRole.superAdmin,
    UserRole.groupAdmin,
    UserRole.schoolAdmin,
    UserRole.hod,
    UserRole.teacher,
    UserRole.transportManager,
  };

  /// Transport's fleet and trip screens are the office's; the bus crew run
  /// their own routes from My Trip instead.
  static const _notAttendants = {UserRole.busAttendant, UserRole.driver};

  static const transport = NavGroup(
    label: 'Transport',
    items: [
      NavItem(
        path: '/my-trip',
        module: AppModules.transport,
        // Their own routes, and only theirs - the API scopes it, so no level
        // is asked of the matrix beyond the module being on.
        requiredLevel: PermissionLevel.none,
        label: 'My Trip',
        icon: Icons.directions_bus_filled,
        allowedRoles: {UserRole.busAttendant, UserRole.driver},
        pageTitle: 'My Trip',
        pageSubtitle: "Today's trips on your routes",
      ),
      NavItem(
        path: '/transport/vehicles',
        module: AppModules.transport,
        deniedRoles: _notAttendants,
        label: 'Vehicles',
        icon: Icons.directions_bus_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'Vehicles',
        pageSubtitle: 'School buses and their seating capacity',
      ),
      NavItem(
        path: '/transport/drivers',
        module: AppModules.transport,
        deniedRoles: _notAttendants,
        label: 'Crew',
        icon: Icons.badge_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'Bus crew',
        pageSubtitle: 'Drivers and attendants, their licences and their phones',
      ),
      NavItem(
        path: '/transport/bus-stops',
        module: AppModules.transport,
        deniedRoles: _notAttendants,
        label: 'Bus Stops',
        icon: Icons.location_on_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'Bus Stops',
        // The places, as opposed to one route calling at one of them -
        // which is what Routes & Stops below is about (docs/maps.md).
        pageSubtitle: 'The places the buses stop at',
      ),
      NavItem(
        path: '/transport/routes',
        module: AppModules.transport,
        deniedRoles: _notAttendants,
        label: 'Routes',
        icon: Icons.alt_route_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'Routes & Stops',
        pageSubtitle: 'Bus routes, stops and the students riding them',
      ),
      NavItem(
        path: '/transport/trips',
        module: AppModules.transport,
        deniedRoles: _notAttendants,
        label: 'Trips',
        icon: Icons.route_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'School Transport',
        pageSubtitle: 'Live bus operations and student trip events',
      ),
    ],
  );

  /// The prototype's Operations group sits next to Transport. The message
  /// log holds guardians' numbers, so only admins see it; the inbox is every
  /// user's own mail and is open to all.
  /// Fee Management (docs/fees.md). Each slice adds its screen here - F1 is
  /// the set-up.
  static const fees = NavGroup(
    label: 'Fees',
    items: [
      NavItem(
        path: '/fee-setup',
        module: AppModules.fees,
        requiredLevel: PermissionLevel.view,
        label: 'Fee Setup',
        icon: Icons.request_quote_outlined,
        // The roles with fees in the default matrix - only consulted when
        // the session carries no matrix at all; otherwise the matrix decides,
        // so a school that gives its front desk fees sees them here. A Super
        // Admin reads; the screen offers changes only at "manage".
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.accountant},
        pageTitle: 'Fee Setup',
        pageSubtitle: 'Fee types, class and bus route fees, and installments',
      ),
      NavItem(
        path: '/student-fees',
        module: AppModules.fees,
        requiredLevel: PermissionLevel.view,
        label: 'Student Fees',
        icon: Icons.receipt_long_outlined,
        // What each student owes - the same people as Fee Setup.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.accountant},
        pageTitle: 'Student Fees',
        pageSubtitle: 'What each student has been charged, has paid and still owes',
      ),
      NavItem(
        path: '/fee-receipts',
        module: AppModules.fees,
        requiredLevel: PermissionLevel.view,
        label: 'Receipts',
        icon: Icons.receipt_outlined,
        // Every receipt the school has issued - the same people as Fee Setup.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.accountant},
        pageTitle: 'Receipts',
        pageSubtitle: 'Every fee payment recorded, with its receipt',
      ),
      NavItem(
        path: '/fee-discounts',
        module: AppModules.fees,
        requiredLevel: PermissionLevel.view,
        label: 'Discounts',
        icon: Icons.percent,
        // Every discount the school has given - the same people as Fee Setup.
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.accountant},
        pageTitle: 'Discounts',
        pageSubtitle: 'Discounts given on student fees, and why',
      ),
    ],
  );

  static const operations = NavGroup(
    label: 'Operations',
    items: [
      NavItem(
        path: '/communication',
        module: AppModules.communication,
        requiredLevel: PermissionLevel.manage,
        label: 'Communication',
        icon: Icons.forum_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin},
        pageTitle: 'Communication',
        pageSubtitle: 'SMS, alerts and announcements',
      ),
      NavItem(
        path: '/announcements',
        module: AppModules.announcements,
        label: 'Announcements',
        icon: Icons.campaign_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.groupAdmin, UserRole.schoolAdmin, UserRole.hod},
        pageTitle: 'Announcements',
        pageSubtitle: 'Notices published to the school',
      ),
      NavItem(
        path: '/inbox',
        label: 'My Inbox',
        icon: Icons.inbox_outlined,
        allowedRoles: _everyone,
        pageTitle: 'My Inbox',
        pageSubtitle: 'Messages the school sent you',
      ),
    ],
  );

  static const groups = [overview, people, attendanceHr, academics, transport, operations, fees, administration];

  static List<NavItem> get allItems => groups.expand((g) => g.items).toList();

  static NavItem? findByPath(String path) {
    for (final item in allItems) {
      if (item.path == path) return item;
    }
    return null;
  }

  /// Pages every signed-in user has, reached from the header rather than the
  /// sidebar. They carry a title for the topbar but no [NavItem], so the
  /// router puts no role or module gate on them.
  static const _headerPages = {'/profile': (title: 'My Profile', subtitle: 'Your details, sign-in email and photo')};

  /// The topbar's title and subtitle for [path], or null for a path that has
  /// neither a sidebar entry nor a header page.
  static ({String title, String subtitle})? headingFor(String path) {
    final item = findByPath(path);
    if (item != null) return (title: item.pageTitle, subtitle: item.pageSubtitle);
    return _headerPages[path];
  }
}

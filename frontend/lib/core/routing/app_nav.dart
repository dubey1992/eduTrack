import 'package:flutter/material.dart';

import '../models/user_role.dart';

/// A single navigation destination: the sidebar entry, the page title/
/// subtitle shown in the topbar, and who is allowed to see it - all in one
/// place, so the visible menu and the route access control can never drift
/// apart (this is the router's only source of truth for role gating on
/// these routes; see AppRouter's redirect).
class NavItem {
  const NavItem({
    required this.path,
    required this.label,
    required this.icon,
    required this.allowedRoles,
    required this.pageTitle,
    required this.pageSubtitle,
  });

  final String path;
  final String label;
  final IconData icon;
  final Set<UserRole> allowedRoles;
  final String pageTitle;
  final String pageSubtitle;

  bool allows(UserRole role) => allowedRoles.contains(role);
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
    UserRole.schoolAdmin,
    UserRole.hod,
    UserRole.teacher,
    UserRole.staff,
    UserRole.transportManager,
  };

  static const overview = NavGroup(
    label: 'Overview',
    items: [
      NavItem(
        path: '/dashboard',
        label: 'Dashboard',
        icon: Icons.dashboard_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Dashboard',
        pageSubtitle: 'Daily school operations overview',
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
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin},
        pageTitle: 'Admin Users',
        pageSubtitle: 'School admin accounts and access',
      ),
    ],
  );

  static const academics = NavGroup(
    label: 'Academics',
    items: [
      NavItem(
        path: '/academic-years',
        label: 'Academic Years',
        icon: Icons.calendar_today_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Academic Years',
        pageSubtitle: 'Academic year setup and rollover',
      ),
      NavItem(
        path: '/holidays',
        label: 'Holidays',
        icon: Icons.beach_access_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Holiday Calendar',
        pageSubtitle: 'School holidays and breaks that pause attendance, leave and teaching',
      ),
      NavItem(
        path: '/departments',
        label: 'Departments',
        icon: Icons.corporate_fare_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Departments',
        pageSubtitle: 'Academic departments and HOD assignment',
      ),
      NavItem(
        path: '/subjects',
        label: 'Subjects',
        icon: Icons.menu_book_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Subjects',
        pageSubtitle: 'Subject setup and lead teacher assignment',
      ),
      NavItem(
        path: '/classes',
        label: 'Classes & Sections',
        icon: Icons.school_outlined,
        allowedRoles: _allRoles,
        pageTitle: 'Classes & Sections',
        pageSubtitle: 'Class structure and teacher assignment',
      ),
      NavItem(
        path: '/timetable',
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
        label: 'Student Attendance',
        icon: Icons.fact_check_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin, UserRole.teacher},
        pageTitle: 'Student Attendance',
        pageSubtitle: 'Daily class attendance register',
      ),
      NavItem(
        path: '/staff-attendance',
        label: 'Staff Attendance',
        icon: Icons.badge_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin, UserRole.hod},
        pageTitle: 'Staff Attendance',
        pageSubtitle: 'Daily teacher and staff attendance register',
      ),
      NavItem(
        path: '/leaves',
        label: 'Staff Leave',
        icon: Icons.event_busy_outlined,
        allowedRoles: {
          UserRole.superAdmin,
          UserRole.schoolAdmin,
          UserRole.hod,
          UserRole.teacher,
          UserRole.staff,
          UserRole.transportManager,
        },
        pageTitle: 'Staff Leave',
        pageSubtitle: 'Leave requests, approvals and attendance sync',
      ),
      NavItem(
        path: '/teaching-reports',
        label: 'Teaching Reports',
        icon: Icons.fact_check_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin, UserRole.hod, UserRole.teacher},
        pageTitle: 'Daily Teaching Reports',
        pageSubtitle: 'Scheduled periods, filed reports and HOD review',
      ),
      NavItem(
        path: '/syllabus',
        label: 'Syllabus',
        icon: Icons.menu_book_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin, UserRole.hod, UserRole.teacher},
        pageTitle: 'Syllabus Tracking',
        pageSubtitle: 'Curriculum outline and per-class coverage',
      ),
      NavItem(
        path: '/hod-reports',
        label: 'HOD Reports',
        icon: Icons.insights_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin, UserRole.hod},
        pageTitle: 'HOD / Staff Reports',
        pageSubtitle: 'Attendance and teaching performance by department',
      ),
    ],
  );

  static const people = NavGroup(
    label: 'People',
    items: [
      NavItem(
        path: '/staff',
        label: 'Teachers & Staff',
        icon: Icons.groups_2_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin},
        pageTitle: 'Teachers & Staff',
        pageSubtitle: 'Employee records, departments and assignments',
      ),
      NavItem(
        path: '/students',
        label: 'Students',
        icon: Icons.school_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin, UserRole.teacher},
        pageTitle: 'Student Management',
        pageSubtitle: 'Admissions, profiles and class assignments',
      ),
    ],
  );

  static const _transportViewerRoles = {
    UserRole.superAdmin,
    UserRole.schoolAdmin,
    UserRole.hod,
    UserRole.teacher,
    UserRole.transportManager,
  };

  static const transport = NavGroup(
    label: 'Transport',
    items: [
      NavItem(
        path: '/transport/vehicles',
        label: 'Vehicles',
        icon: Icons.directions_bus_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'Vehicles',
        pageSubtitle: 'School buses and their seating capacity',
      ),
      NavItem(
        path: '/transport/drivers',
        label: 'Drivers',
        icon: Icons.badge_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'Drivers',
        pageSubtitle: 'Bus drivers and their licences',
      ),
      NavItem(
        path: '/transport/routes',
        label: 'Routes',
        icon: Icons.alt_route_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'Routes & Stops',
        pageSubtitle: 'Bus routes, stops and the students riding them',
      ),
      NavItem(
        path: '/transport/trips',
        label: 'Trips',
        icon: Icons.route_outlined,
        allowedRoles: _transportViewerRoles,
        pageTitle: 'School Transport',
        pageSubtitle: 'Live bus operations and student trip events',
      ),
    ],
  );

  static const groups = [overview, people, attendanceHr, academics, transport, administration];

  static List<NavItem> get allItems => groups.expand((g) => g.items).toList();

  static NavItem? findByPath(String path) {
    for (final item in allItems) {
      if (item.path == path) return item;
    }
    return null;
  }
}

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
        path: '/',
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
        label: 'Users',
        icon: Icons.group_outlined,
        allowedRoles: {UserRole.superAdmin, UserRole.schoolAdmin},
        pageTitle: 'Users',
        pageSubtitle: 'Accounts, roles and access',
      ),
    ],
  );

  static const groups = [overview, administration];

  static List<NavItem> get allItems => groups.expand((g) => g.items).toList();

  static NavItem? findByPath(String path) {
    for (final item in allItems) {
      if (item.path == path) return item;
    }
    return null;
  }
}

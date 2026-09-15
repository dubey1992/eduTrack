import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/routing/app_nav.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/core/widgets/school_filter_dropdown.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/schools/application/school_list_notifier.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:edutrack_app/features/schools/presentation/widgets/parent_school_field.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_repository.dart';

School _school({
  required int id,
  required String name,
  int? parentSchoolId,
  String? parentSchoolName,
  int branchCount = 0,
}) {
  return School(
    id: id,
    name: name,
    parentSchoolId: parentSchoolId,
    parentSchoolName: parentSchoolName,
    branchCount: branchCount,
    registrationNumber: null,
    email: '$id@example.test',
    phone: '+91 9876543210',
    address: '1 Road',
    city: 'Pune',
    state: 'MH',
    country: 'India',
    postalCode: '411001',
    currencyCode: 'INR',
    timezone: 'UTC',
    logoUrl: null,
    status: SchoolStatus.active,
  );
}

final _group = _school(id: 1, name: "St Mary's Group", branchCount: 2);
final _north = _school(id: 2, name: "St Mary's North", parentSchoolId: 1, parentSchoolName: "St Mary's Group");
final _standalone = _school(id: 3, name: 'Elsewhere High');

/// School groups on the client: the role, the navigation it gets, the branch
/// filter, and the parent picker's refusal to offer impossible choices.
void main() {
  group('the role', () {
    test('reads and writes the API value the backend uses', () {
      expect(UserRole.fromApiValue('GROUP_ADMIN'), UserRole.groupAdmin);
      expect(UserRole.groupAdmin.apiValue, 'GROUP_ADMIN');
      expect(UserRole.groupAdmin.label, 'Group Admin');
    });

    test('a session carrying the new role parses', () {
      final user = AuthenticatedUser.fromJson({
        'id': 1,
        'name': 'Anita Rao',
        'email': 'anita@example.test',
        'role': 'GROUP_ADMIN',
      });

      expect(user.role, UserRole.groupAdmin);
    });
  });

  group('navigation', () {
    // The sidebar and the route guard share this config, so a role missing
    // from it would be locked out of screens the API lets it use.
    test('a group admin reaches everything a school admin reaches', () {
      for (final item in AppNav.allItems) {
        if (item.allows(UserRole.schoolAdmin)) {
          expect(
            item.allows(UserRole.groupAdmin),
            isTrue,
            reason: '${item.path} is open to a School Admin but not a Group Admin',
          );
        }
      }
    });

    test('but not the two platform screens', () {
      // Onboarding schools and recording payments stay Super Admin.
      for (final path in ['/schools', '/payments']) {
        final item = AppNav.findByPath(path)!;
        expect(item.allows(UserRole.groupAdmin), isFalse, reason: '$path must stay Super Admin only');
        expect(item.allows(UserRole.superAdmin), isTrue);
      }
    });
  });

  group('the branch filter', () {
    Widget wrap(UserRole role, List<School> schools) {
      return ProviderScope(
        overrides: [
          authRepositoryProvider.overrideWithValue(
            FakeAuthRepository(
              sessionOnRestore: AuthenticatedUser(id: 1, name: 'Someone', email: 'someone@example.test', role: role),
            ),
          ),
          schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: schools)),
        ],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(body: SchoolFilterDropdown(selected: null, onChanged: (_) {})),
        ),
      );
    }

    testWidgets('a group admin gets one, worded as branches', (tester) async {
      await tester.pumpWidget(wrap(UserRole.groupAdmin, [_group, _north]));
      await tester.pumpAndSettle();

      expect(find.text('Filter by branch'), findsOneWidget);
      expect(find.text('Whole group'), findsWidgets);
    });

    testWidgets('a super admin still gets the school wording', (tester) async {
      await tester.pumpWidget(wrap(UserRole.superAdmin, [_group, _standalone]));
      await tester.pumpAndSettle();

      expect(find.text('Filter by school'), findsOneWidget);
      expect(find.text('All Schools'), findsWidgets);
    });

    testWidgets('nobody else gets one at all', (tester) async {
      await tester.pumpWidget(wrap(UserRole.schoolAdmin, [_group]));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
    });
  });

  group('the parent picker', () {
    Widget wrap(List<School> schools, {School? editing, int? value}) {
      return ProviderScope(
        overrides: [schoolRepositoryProvider.overrideWithValue(FakeSchoolRepository(schools: schools))],
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: ParentSchoolField(value: value, editing: editing, onChanged: (_) {}),
          ),
        ),
      );
    }

    testWidgets('offers standalone schools as possible parents', (tester) async {
      await tester.pumpWidget(wrap([_group, _standalone]));
      await tester.pumpAndSettle();

      expect(find.text('Standalone school'), findsWidgets);

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      expect(find.text('Branch of Elsewhere High').hitTestable(), findsOneWidget);
    });

    testWidgets('never offers a branch as a parent', (tester) async {
      // A group is one level deep; the API refuses this, so the form should
      // not offer it.
      await tester.pumpWidget(wrap([_group, _north]));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      expect(find.textContaining("Branch of St Mary's North"), findsNothing);
      expect(find.text("Branch of St Mary's Group").hitTestable(), findsOneWidget);
    });

    testWidgets('never offers a school as its own parent', (tester) async {
      await tester.pumpWidget(wrap([_group, _standalone], editing: _standalone));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<int?>));
      await tester.pumpAndSettle();

      expect(find.textContaining('Branch of Elsewhere High'), findsNothing);
    });

    testWidgets('disappears for a school that already has branches', (tester) async {
      // It cannot become a branch, so there is nothing to choose.
      await tester.pumpWidget(wrap([_group, _standalone], editing: _group));
      await tester.pumpAndSettle();

      expect(find.byType(DropdownButtonFormField<int?>), findsNothing);
    });
  });

  group('the school model', () {
    test('reads where a school sits in its group', () {
      final branch = School.fromJson({
        'id': 2,
        'name': "St Mary's North",
        'parent_school_id': 1,
        'parent_school_name': "St Mary's Group",
        'branch_count': 0,
        'email': 'n@example.test',
        'phone': '+91 9876543210',
        'address': '1 Road',
        'city': 'Pune',
        'state': 'MH',
        'country': 'India',
        'postal_code': '411001',
        'currency_code': 'INR',
        'status': 'active',
      });

      expect(branch.isBranch, isTrue);
      expect(branch.isGroupParent, isFalse);
      expect(branch.parentSchoolName, "St Mary's Group");
    });

    test('a school with no group says so', () {
      expect(_standalone.isBranch, isFalse);
      expect(_standalone.isGroupParent, isFalse);
    });

    test('a parent counts its branches', () {
      expect(_group.isGroupParent, isTrue);
      expect(_group.branchCount, 2);
    });
  });
}

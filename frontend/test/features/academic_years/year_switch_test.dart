import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/storage/key_value_store.dart';
import 'package:edutrack_app/core/theme/app_colors.dart';
import 'package:edutrack_app/core/theme/app_theme.dart';
import 'package:edutrack_app/features/academic_years/application/viewed_year.dart';
import 'package:edutrack_app/features/academic_years/data/academic_year_repository.dart';
import 'package:edutrack_app/features/academic_years/data/models/academic_year.dart';
import 'package:edutrack_app/features/academic_years/presentation/year_switch.dart';
import 'package:edutrack_app/features/auth/data/auth_repository.dart';
import 'package:edutrack_app/features/auth/data/models/authenticated_user.dart';
import 'package:edutrack_app/features/classes/application/school_class_list_notifier.dart';
import 'package:edutrack_app/features/classes/data/models/school_class.dart';
import 'package:edutrack_app/features/classes/data/school_class_repository.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_academic_year_repository.dart';
import '../../support/fake_auth_repository.dart';
import '../../support/fake_school_class_repository.dart';
import '../../support/in_memory_key_value_store.dart';

const _admin = AuthenticatedUser(
  id: 2,
  name: 'Anita Sharma',
  email: 'anita@example.com',
  role: UserRole.schoolAdmin,
  schoolId: 1,
);
const _root = AuthenticatedUser(id: 1, name: 'Root', email: 'root@example.com', role: UserRole.superAdmin);

AcademicYear _year(int id, String name, int start, {bool current = false}) => AcademicYear(
  id: id,
  schoolId: 1,
  schoolName: 'Sunrise',
  name: name,
  startDate: DateTime(start, 4, 1),
  endDate: DateTime(start + 1, 3, 31),
  isCurrent: current,
);

final _last = _year(1, '2025-26', 2025);
final _this = _year(2, '2026-27', 2026, current: true);
final _next = _year(3, '2027-28', 2027);

SchoolClass _class(int id, String name, int yearId) => SchoolClass(
  id: id,
  schoolId: 1,
  schoolName: 'Sunrise',
  academicYearId: yearId,
  academicYearName: yearId == 1 ? '2025-26' : '2026-27',
  name: name,
  level: 5,
  sections: const [],
);

Future<InMemoryKeyValueStore> _pump(WidgetTester tester, {AuthenticatedUser user = _admin, String? remembered}) async {
  final store = InMemoryKeyValueStore();
  if (remembered != null) store.values['viewed_academic_year_1'] = remembered;

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: user)),
        academicYearRepositoryProvider.overrideWithValue(FakeAcademicYearRepository(years: [_last, _this, _next])),
        keyValueStoreProvider.overrideWithValue(store),
      ],
      child: MaterialApp(
        theme: AppTheme.light(),
        home: const Scaffold(body: Center(child: YearSwitch())),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return store;
}

String _label(WidgetTester tester) => tester.widget<Text>(find.byKey(const Key('year-switch-label'))).data!;

/// One academic-year switch in the top bar, followed by every year-based
/// screen (decided 2026-11-05).
void main() {
  testWidgets('opens on the current year', (tester) async {
    await _pump(tester);

    expect(_label(tester), 'Year 2026-27 (current)');
  });

  testWidgets('lists every year, newest first, and switching is remembered on this device', (tester) async {
    final store = await _pump(tester);

    await tester.tap(find.byKey(const Key('year-switch')));
    await tester.pumpAndSettle();

    expect(find.text('2027-28 (next year)'), findsOneWidget);
    expect(find.text('2025-26 (past year)'), findsOneWidget);
    final top = tester.getTopLeft(find.text('2027-28 (next year)')).dy;
    expect(top, lessThan(tester.getTopLeft(find.text('2025-26 (past year)')).dy));

    await tester.tap(find.text('2025-26 (past year)'));
    await tester.pumpAndSettle();

    expect(_label(tester), 'Year 2025-26 (past year)');
    expect(store.values['viewed_academic_year_1'], '1');
  });

  testWidgets('a past year is marked in the warning colours', (tester) async {
    await _pump(tester, remembered: '1');

    final box = tester.widget<Container>(
      find.descendant(of: find.byKey(const Key('year-switch')), matching: find.byType(Container)).first,
    );
    expect((box.decoration! as BoxDecoration).color, AppColors.light.warningContainer);
  });

  testWidgets('going back to the current year forgets the choice', (tester) async {
    final store = await _pump(tester, remembered: '1');

    await tester.tap(find.byKey(const Key('year-switch')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('2026-27 (current)'));
    await tester.pumpAndSettle();

    expect(_label(tester), 'Year 2026-27 (current)');
    expect(store.values.containsKey('viewed_academic_year_1'), isFalse);
  });

  testWidgets('a remembered year that no longer exists falls back to the current one', (tester) async {
    await _pump(tester, remembered: '99');

    expect(_label(tester), 'Year 2026-27 (current)');
  });

  testWidgets('a Super Admin, who picks a school on each screen, has no switch', (tester) async {
    await _pump(tester, user: _root);

    expect(find.byKey(const Key('year-switch')), findsNothing);
  });

  test('the class list asks for the year in view', () async {
    final classes = FakeSchoolClassRepository(classes: [_class(1, 'Class 5', 1), _class(2, 'Class 6', 2)]);
    final container = ProviderContainer(
      overrides: [
        authRepositoryProvider.overrideWithValue(FakeAuthRepository(sessionOnRestore: _admin)),
        academicYearRepositoryProvider.overrideWithValue(FakeAcademicYearRepository(years: [_last, _this, _next])),
        keyValueStoreProvider.overrideWithValue(InMemoryKeyValueStore()),
        schoolClassRepositoryProvider.overrideWithValue(classes),
      ],
    );
    addTearDown(container.dispose);

    var list = await container.read(schoolClassListNotifierProvider.future);
    expect(list.items.map((c) => c.name), ['Class 6']);

    await container.read(viewedYearIdProvider.notifier).choose(1);
    list = await container.read(schoolClassListNotifierProvider.future);
    expect(list.items.map((c) => c.name), ['Class 5']);
  });
}

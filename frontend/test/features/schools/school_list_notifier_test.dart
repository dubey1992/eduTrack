import 'package:edutrack_app/features/schools/application/school_list_notifier.dart';
import 'package:edutrack_app/features/schools/data/models/school.dart';
import 'package:edutrack_app/features/schools/data/school_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_school_repository.dart';

const _school = School(
  id: 1,
  name: 'Sunrise Public School',
  registrationNumber: null,
  email: 'admin@sunriseschool.edu',
  phone: '+91 98765 43210',
  address: '12 School Road',
  city: 'New Delhi',
  state: 'Delhi',
  country: 'India',
  postalCode: '110001',
  currencyCode: 'INR',
  timezone: 'UTC',
  logoUrl: null,
  status: SchoolStatus.active,
);

void main() {
  ProviderContainer makeContainer(FakeSchoolRepository fake) {
    return ProviderContainer(overrides: [schoolRepositoryProvider.overrideWithValue(fake)]);
  }

  // This unpaginated provider backs picker-style consumers (e.g. the school
  // filter dropdown and every "Add X" dialog's school picker) - it
  // deliberately has no create/setActive methods of its own; SchoolPageNotifier
  // (see school_page_notifier_test.dart) owns those and keeps this provider in
  // sync via invalidation.
  test('build() loads every school, unpaginated', () async {
    final container = makeContainer(FakeSchoolRepository(schools: [_school]));
    addTearDown(container.dispose);

    final result = await container.read(schoolListNotifierProvider.future);

    expect(result, hasLength(1));
    expect(result.first.currencyCode, 'INR');
  });

  test('refresh() re-fetches the full list', () async {
    final fake = FakeSchoolRepository(schools: [_school]);
    final container = makeContainer(fake);
    addTearDown(container.dispose);
    await container.read(schoolListNotifierProvider.future);

    await container.read(schoolListNotifierProvider.notifier).refresh();

    final state = container.read(schoolListNotifierProvider).value;
    expect(state, hasLength(1));
  });
}

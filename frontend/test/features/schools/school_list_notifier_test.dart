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
  logoUrl: null,
  status: SchoolStatus.active,
);

void main() {
  ProviderContainer makeContainer(FakeSchoolRepository fake) {
    return ProviderContainer(overrides: [schoolRepositoryProvider.overrideWithValue(fake)]);
  }

  test('build() loads the initial school list', () async {
    final container = makeContainer(FakeSchoolRepository(schools: [_school]));
    addTearDown(container.dispose);

    final result = await container.read(schoolListNotifierProvider.future);

    expect(result, hasLength(1));
    expect(result.first.currencyCode, 'INR');
  });

  test('createSchool() adds the new school to the list', () async {
    final container = makeContainer(FakeSchoolRepository());
    addTearDown(container.dispose);
    await container.read(schoolListNotifierProvider.future);

    await container
        .read(schoolListNotifierProvider.notifier)
        .createSchool(
          name: 'Green Valley School',
          email: 'admin@greenvalley.edu',
          phone: '+234 800 000 0000',
          address: '5 Valley Road',
          city: 'Lagos',
          state: 'Lagos',
          country: 'Nigeria',
          postalCode: '100001',
          currencyCode: 'NGN',
        );

    final state = container.read(schoolListNotifierProvider).value;
    expect(state, hasLength(1));
    expect(state!.first.currencyCode, 'NGN');
  });

  test('setActive() updates that school in place', () async {
    final container = makeContainer(FakeSchoolRepository(schools: [_school]));
    addTearDown(container.dispose);
    await container.read(schoolListNotifierProvider.future);

    await container.read(schoolListNotifierProvider.notifier).setActive(_school, false);

    final state = container.read(schoolListNotifierProvider).value;
    expect(state!.first.status, SchoolStatus.inactive);
  });
}

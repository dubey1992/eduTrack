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

School _schoolWithId(int id) => School(
  id: id,
  name: 'School $id',
  registrationNumber: null,
  email: 'admin$id@school.edu',
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

  test('build() loads the initial page of schools', () async {
    final container = makeContainer(FakeSchoolRepository(schools: [_school]));
    addTearDown(container.dispose);

    final result = await container.read(schoolPageNotifierProvider.future);

    expect(result.items, hasLength(1));
    expect(result.items.first.currencyCode, 'INR');
  });

  test('createSchool() adds the new school and returns to page 1', () async {
    final container = makeContainer(FakeSchoolRepository());
    addTearDown(container.dispose);
    await container.read(schoolPageNotifierProvider.future);

    await container
        .read(schoolPageNotifierProvider.notifier)
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
          timezone: 'UTC',
        );

    final state = container.read(schoolPageNotifierProvider).value;
    expect(state!.items, hasLength(1));
    expect(state.items.first.currencyCode, 'NGN');
  });

  test('updateSchool() saves the changes in place', () async {
    final container = makeContainer(FakeSchoolRepository(schools: [_school]));
    addTearDown(container.dispose);
    await container.read(schoolPageNotifierProvider.future);

    await container
        .read(schoolPageNotifierProvider.notifier)
        .updateSchool(_school, name: 'Sunrise International School', city: 'Gurugram');

    final state = container.read(schoolPageNotifierProvider).value;
    expect(state!.items.first.name, 'Sunrise International School');
    expect(state.items.first.city, 'Gurugram');
  });

  test('updating a school also invalidates the unpaginated picker provider', () async {
    final container = makeContainer(FakeSchoolRepository(schools: [_school]));
    addTearDown(container.dispose);
    await container.read(schoolListNotifierProvider.future);
    await container.read(schoolPageNotifierProvider.future);

    await container.read(schoolPageNotifierProvider.notifier).updateSchool(_school, name: 'Renamed School');

    final pickerState = await container.read(schoolListNotifierProvider.future);
    expect(pickerState.first.name, 'Renamed School');
  });

  test('setActive() updates that school in place', () async {
    final container = makeContainer(FakeSchoolRepository(schools: [_school]));
    addTearDown(container.dispose);
    await container.read(schoolPageNotifierProvider.future);

    await container.read(schoolPageNotifierProvider.notifier).setActive(_school, false);

    final state = container.read(schoolPageNotifierProvider).value;
    expect(state!.items.first.status, SchoolStatus.inactive);
  });

  test('creating a school also invalidates the unpaginated picker provider', () async {
    final container = makeContainer(FakeSchoolRepository());
    addTearDown(container.dispose);
    await container.read(schoolListNotifierProvider.future);
    await container.read(schoolPageNotifierProvider.future);

    await container
        .read(schoolPageNotifierProvider.notifier)
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
          timezone: 'UTC',
        );

    final pickerState = await container.read(schoolListNotifierProvider.future);
    expect(pickerState, hasLength(1));
    expect(pickerState.first.name, 'Green Valley School');
  });

  test('goToPage() and setPerPage() page through the list', () async {
    final container = makeContainer(FakeSchoolRepository(schools: [for (var i = 1; i <= 25; i++) _schoolWithId(i)]));
    addTearDown(container.dispose);
    await container.read(schoolPageNotifierProvider.future);

    await container.read(schoolPageNotifierProvider.notifier).goToPage(2);
    var state = container.read(schoolPageNotifierProvider).value!;
    expect(state.currentPage, 2);
    expect(state.items, hasLength(5));

    await container.read(schoolPageNotifierProvider.notifier).setPerPage(50);
    state = container.read(schoolPageNotifierProvider).value!;
    expect(state.currentPage, 1);
    expect(state.items, hasLength(25));
  });
}

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/models/school.dart';
import '../data/school_repository.dart';

final schoolListNotifierProvider = AsyncNotifierProvider<SchoolListNotifier, List<School>>(
  SchoolListNotifier.new,
);

class SchoolListNotifier extends AsyncNotifier<List<School>> {
  @override
  Future<List<School>> build() {
    return ref.read(schoolRepositoryProvider).list();
  }

  Future<void> refresh() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(schoolRepositoryProvider).list());
  }

  Future<void> createSchool({
    required String name,
    String? registrationNumber,
    required String email,
    required String phone,
    required String address,
    required String city,
    required String state,
    required String country,
    required String postalCode,
    required String currencyCode,
  }) async {
    await ref
        .read(schoolRepositoryProvider)
        .create(
          name: name,
          registrationNumber: registrationNumber,
          email: email,
          phone: phone,
          address: address,
          city: city,
          state: state,
          country: country,
          postalCode: postalCode,
          currencyCode: currencyCode,
        );
    await refresh();
  }

  Future<void> setActive(School school, bool active) async {
    final updated = await ref.read(schoolRepositoryProvider).setActive(school.id, active);

    state = state.whenData(
      (schools) => [for (final existing in schools) existing.id == updated.id ? updated : existing],
    );
  }
}

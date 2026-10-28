import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/company_details_repository.dart';
import '../data/models/company_details.dart';

final companyDetailsNotifierProvider = AsyncNotifierProvider<CompanyDetailsNotifier, CompanyDetails>(
  CompanyDetailsNotifier.new,
  // No automatic retry: a refusal is an answer, and the screen offers its
  // own Retry.
  retry: (retryCount, error) => null,
);

/// The Company details screen's state. A failed save leaves the loaded
/// details in place and lets the error through to the form; only a failed
/// load puts the screen into its error state.
class CompanyDetailsNotifier extends AsyncNotifier<CompanyDetails> {
  @override
  Future<CompanyDetails> build() => ref.read(companyDetailsRepositoryProvider).get();

  Future<void> load() async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() => ref.read(companyDetailsRepositoryProvider).get());
  }

  Future<void> save(Map<String, String> fields) async {
    state = AsyncData(await ref.read(companyDetailsRepositoryProvider).save(fields));
  }
}

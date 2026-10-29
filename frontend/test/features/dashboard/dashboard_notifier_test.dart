import 'dart:async';

import 'package:edutrack_app/features/dashboard/application/dashboard_notifier.dart';
import 'package:edutrack_app/features/dashboard/data/dashboard_repository.dart';
import 'package:edutrack_app/features/dashboard/data/models/dashboard.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_dashboard_repository.dart';

/// Answers each fetch only when the test says so, so what the screen shows
/// *while* the figures are on their way can be looked at.
class _SlowDashboardRepository extends FakeDashboardRepository {
  Completer<Dashboard>? pending;

  @override
  Future<Dashboard> fetch({int? schoolId}) {
    lastSchoolId = schoolId;
    pending = Completer<Dashboard>();

    return pending!.future;
  }
}

void main() {
  late _SlowDashboardRepository repository;
  late ProviderContainer container;

  setUp(() async {
    repository = _SlowDashboardRepository();
    container = ProviderContainer(overrides: [dashboardRepositoryProvider.overrideWithValue(repository)]);
    addTearDown(container.dispose);

    container.listen(dashboardNotifierProvider, (_, _) {});
    repository.pending!.complete(defaultDashboard);
    await container.read(dashboardNotifierProvider.future);
  });

  test('coming back keeps the figures on screen while new ones load', () async {
    final notifier = container.read(dashboardNotifierProvider.notifier);

    final reading = notifier.refresh(keepFigures: true);

    // Not a loader: swapping the page for one collapsed it under
    // somebody's scroll, and it jumped when the figures came back.
    expect(container.read(dashboardNotifierProvider), isA<AsyncData<Dashboard>>());

    repository.pending!.complete(defaultDashboard);
    await reading;
    expect(container.read(dashboardNotifierProvider).value, defaultDashboard);
  });

  test('Refresh, asked for by hand, shows that it is loading', () async {
    final reading = container.read(dashboardNotifierProvider.notifier).refresh();

    expect(container.read(dashboardNotifierProvider), isA<AsyncLoading<Dashboard>>());

    repository.pending!.complete(defaultDashboard);
    await reading;
  });

  test("another school's figures are never shown under the old one's", () async {
    final reading = container.read(dashboardNotifierProvider.notifier).setSchoolFilter(7);

    expect(container.read(dashboardNotifierProvider), isA<AsyncLoading<Dashboard>>());
    expect(repository.lastSchoolId, 7);

    repository.pending!.complete(defaultDashboard);
    await reading;
  });
}

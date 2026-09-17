import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payroll/application/payroll_notifiers.dart';
import 'package:edutrack_app/features/payroll/data/models/payroll.dart';
import 'package:edutrack_app/features/payroll/data/payroll_repository.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../support/fake_payroll_repository.dart';

ProviderContainer containerWith(FakePayrollRepository fake) {
  final container = ProviderContainer(
    overrides: [payrollRepositoryProvider.overrideWithValue(fake)],
    retry: (retryCount, error) => null,
  );
  addTearDown(container.dispose);

  return container;
}

void main() {
  group('salaries', () {
    test('saving replaces the row in place', () async {
      final fake = FakePayrollRepository(
        employees: [
          fakeEmployee(),
          fakeEmployee(id: 2, name: 'Asha Rao', employeeId: 'STF-1'),
        ],
      );
      final container = containerWith(fake);
      final subscription = container.listen(salaryListNotifierProvider, (_, _) {});
      addTearDown(subscription.close);
      final page = await container.read(salaryListNotifierProvider.future);

      await container
          .read(salaryListNotifierProvider.notifier)
          .save(page.items.first, basicSalary: '30000', components: const []);

      final rows = container.read(salaryListNotifierProvider).value!.items;
      expect(rows.first.salary!.basicSalary, '30000.00');
      expect(rows, hasLength(2));
      expect(fake.calls.where((call) => call == 'salaries'), hasLength(1), reason: 'no reload needed');
    });

    test('with "no salary yet" on, a saved employee leaves the list', () async {
      final fake = FakePayrollRepository(
        employees: [
          fakeEmployee(),
          fakeEmployee(id: 2, name: 'Asha Rao', employeeId: 'STF-1'),
        ],
      );
      final container = containerWith(fake);
      final subscription = container.listen(salaryListNotifierProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(salaryListNotifierProvider.future);
      final notifier = container.read(salaryListNotifierProvider.notifier);

      await notifier.setMissingOnly(true);
      final missing = container.read(salaryListNotifierProvider).value!.items;
      await notifier.save(missing.first, basicSalary: '15000', components: const []);

      expect(container.read(salaryListNotifierProvider).value!.items.map((e) => e.name), ['Asha Rao']);
    });
  });

  group('a run', () {
    test('generating goes back to the first page and returns the draft', () async {
      final fake = FakePayrollRepository();
      final container = containerWith(fake);
      final subscription = container.listen(payrollRunListNotifierProvider, (_, _) {});
      addTearDown(subscription.close);
      await container.read(payrollRunListNotifierProvider.future);

      final run = await container.read(payrollRunListNotifierProvider.notifier).generate(year: 2026, month: 9);

      expect(run.status, PayrollRunStatus.draft);
      expect(container.read(payrollRunListNotifierProvider).value!.items.single.periodLabel, 'September 2026');
    });

    test('a refused action still re-reads the run and passes the failure on', () async {
      final fake = FakePayrollRepository(
        failWith: {'finalize': const Failure(code: 'PAYROLL_RUN_LOCKED', message: 'Locked.')},
      );
      await fake.generate(year: 2026, month: 9);
      final container = containerWith(fake);
      final subscription = container.listen(payrollRunNotifierProvider(1), (_, _) {});
      addTearDown(subscription.close);
      await container.read(payrollRunNotifierProvider(1).future);

      await expectLater(container.read(payrollRunNotifierProvider(1).notifier).finalize(), throwsA(isA<Failure>()));

      expect(container.read(payrollRunNotifierProvider(1)).value!.run.status, PayrollRunStatus.draft);
      expect(fake.calls.where((call) => call == 'run'), hasLength(2));
    });

    test('paying everyone marks the run paid', () async {
      final fake = FakePayrollRepository();
      await fake.generate(year: 2026, month: 9);
      await fake.finalize(1);
      final container = containerWith(fake);
      final subscription = container.listen(payrollRunNotifierProvider(1), (_, _) {});
      addTearDown(subscription.close);
      await container.read(payrollRunNotifierProvider(1).future);

      await container
          .read(payrollRunNotifierProvider(1).notifier)
          .payAll(paidOn: DateTime(2026, 9, 30), mode: PaymentMode.cash);

      final view = container.read(payrollRunNotifierProvider(1)).value!;
      expect((view.run.status, view.run.unpaidCount), (PayrollRunStatus.paid, 0));
    });
  });
}

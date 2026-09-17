import 'package:edutrack_app/core/errors/failure.dart';
import 'package:edutrack_app/core/models/user_role.dart';
import 'package:edutrack_app/core/network/paginated_response.dart';
import 'package:edutrack_app/features/payments/data/models/payment.dart';
import 'package:edutrack_app/features/payroll/data/models/payroll.dart';
import 'package:edutrack_app/features/payroll/data/payroll_repository.dart';

import 'fake_pagination.dart';

EmployeeSalary fakeEmployee({
  int id = 1,
  String name = 'Rahul Verma',
  String employeeId = 'TCH-1',
  UserRole role = UserRole.teacher,
  String? basic,
  List<SalaryComponent> components = const [],
}) {
  return EmployeeSalary(
    staffProfileId: id,
    employeeId: employeeId,
    name: name,
    role: role,
    schoolId: 1,
    schoolName: 'Sunrise Public School',
    schoolCurrencyCode: 'INR',
    designation: 'Teacher',
    departmentName: 'Science',
    salary: basic == null ? null : fakeSalary(basic, components),
  );
}

Salary fakeSalary(String basic, List<SalaryComponent> components) {
  double sum(PayComponentType type) =>
      components.where((c) => c.type == type).fold(0, (total, c) => total + double.parse(c.amount));
  final gross = double.parse(basic) + sum(PayComponentType.earning);
  final deductions = sum(PayComponentType.deduction);

  return Salary(
    basicSalary: double.parse(basic).toStringAsFixed(2),
    currencyCode: 'INR',
    components: components,
    totalEarnings: sum(PayComponentType.earning).toStringAsFixed(2),
    totalDeductions: deductions.toStringAsFixed(2),
    grossMonthly: gross.toStringAsFixed(2),
    netMonthly: (gross - deductions).toStringAsFixed(2),
  );
}

/// Payroll kept in memory, with the state rules the API enforces: one run a
/// month, adjustments only on a draft, payment only once finalized. Pay is
/// not pro-rated here - that arithmetic is the server's, and is tested there.
class FakePayrollRepository implements PayrollRepository {
  FakePayrollRepository({List<EmployeeSalary>? employees, this.failWith = const {}})
    : employees = employees ?? [fakeEmployee(basic: '30000')];

  final List<EmployeeSalary> employees;
  final List<PayrollRun> storedRuns = [];
  final Map<int, List<Payslip>> payslipsByRun = {};

  /// Method name -> the failure it throws, e.g. {'finalize': Failure(...)}.
  final Map<String, Failure> failWith;
  final List<String> calls = [];

  void _enter(String method) {
    calls.add(method);
    final failure = failWith[method];
    if (failure != null) throw failure;
  }

  @override
  Future<PaginatedResponse<EmployeeSalary>> salaries({
    int? schoolId,
    String? search,
    bool missingOnly = false,
    required int page,
    required int perPage,
  }) async {
    _enter('salaries');
    final filtered = employees
        .where((e) => !missingOnly || e.salary == null)
        .where((e) => search == null || e.name.toLowerCase().contains(search.toLowerCase()))
        .toList();

    return paginateFake(filtered, page: page, perPage: perPage);
  }

  @override
  Future<EmployeeSalary> saveSalary(
    int staffProfileId, {
    required String basicSalary,
    required List<SalaryComponent> components,
  }) async {
    _enter('saveSalary');
    final index = employees.indexWhere((e) => e.staffProfileId == staffProfileId);
    final old = employees[index];
    final updated = fakeEmployee(
      id: old.staffProfileId,
      name: old.name,
      employeeId: old.employeeId,
      role: old.role,
      basic: basicSalary,
      components: components,
    );
    employees[index] = updated;

    return updated;
  }

  @override
  Future<PaginatedResponse<PayrollRun>> runs({int? schoolId, required int page, required int perPage}) async {
    _enter('runs');
    return paginateFake([for (final run in storedRuns) _withTotals(run)], page: page, perPage: perPage);
  }

  @override
  Future<PayrollRun> generate({required int year, required int month, int? schoolId}) async {
    _enter('generate');
    final id = storedRuns.length + 1;
    final run = _run(id: id, year: year, month: month, status: PayrollRunStatus.draft);
    storedRuns.add(run);
    payslipsByRun[id] = [
      for (final employee in employees.where((e) => e.salary != null))
        _payslip(id * 100 + employee.staffProfileId, run, employee, double.parse(employee.salary!.netMonthly)),
    ];

    return _withTotals(run);
  }

  @override
  Future<PayrollRun> run(int runId) async {
    _enter('run');
    return _withTotals(storedRuns.firstWhere((r) => r.id == runId));
  }

  @override
  Future<PaginatedResponse<Payslip>> runPayslips(
    int runId, {
    String? search,
    required int page,
    required int perPage,
  }) async {
    _enter('runPayslips');
    return paginateFake(payslipsByRun[runId] ?? [], page: page, perPage: perPage);
  }

  @override
  Future<PayrollRun> regenerate(int runId) async {
    _enter('regenerate');
    return _withTotals(storedRuns.firstWhere((r) => r.id == runId));
  }

  @override
  Future<PayrollRun> finalize(int runId) async {
    _enter('finalize');
    _setStatus(runId, PayrollRunStatus.finalized);
    return run(runId);
  }

  @override
  Future<void> deleteRun(int runId) async {
    _enter('deleteRun');
    storedRuns.removeWhere((r) => r.id == runId);
    payslipsByRun.remove(runId);
  }

  @override
  Future<PayrollRun> payRun(int runId, {required DateTime paidOn, required PaymentMode mode, String? reference}) async {
    _enter('payRun');
    payslipsByRun[runId] = [for (final slip in payslipsByRun[runId]!) _paid(slip, mode, reference)];
    _setStatus(runId, PayrollRunStatus.paid);
    return run(runId);
  }

  @override
  Future<Payslip> payslip(int payslipId) async {
    _enter('payslip');
    return _find(payslipId);
  }

  @override
  Future<Payslip> addAdjustment(
    int payslipId, {
    required PayComponentType type,
    required String name,
    required String amount,
    required String note,
  }) async {
    _enter('addAdjustment');
    final slip = _find(payslipId);
    final value = double.parse(amount);
    final line = PayslipLine(
      id: 900 + slip.lines.length,
      type: type,
      name: name,
      amount: value.toStringAsFixed(2),
      isAdjustment: true,
      note: note,
    );
    final net = double.parse(slip.netPay) + (type == PayComponentType.earning ? value : -value);

    return _replace(_payslip(slip.id, _runOf(slip), null, net, lines: [...slip.lines, line], from: slip));
  }

  @override
  Future<Payslip> removeAdjustment(int payslipId, int lineId) async {
    _enter('removeAdjustment');
    final slip = _find(payslipId);
    final line = slip.lines.firstWhere((l) => l.id == lineId);
    final value = double.parse(line.amount);
    final net = double.parse(slip.netPay) - (line.type == PayComponentType.earning ? value : -value);

    return _replace(
      _payslip(
        slip.id,
        _runOf(slip),
        null,
        net,
        lines: [
          for (final l in slip.lines)
            if (l.id != lineId) l,
        ],
        from: slip,
      ),
    );
  }

  @override
  Future<Payslip> payPayslip(
    int payslipId, {
    required DateTime paidOn,
    required PaymentMode mode,
    String? reference,
  }) async {
    _enter('payPayslip');
    return _replace(_paid(_find(payslipId), mode, reference));
  }

  @override
  Future<Payslip> emailPayslip(int payslipId) async {
    _enter('emailPayslip');
    return _find(payslipId);
  }

  @override
  Future<List<int>> downloadPayslip(int payslipId) async {
    _enter('downloadPayslip');
    return const [37, 80, 68, 70];
  }

  @override
  Future<PaginatedResponse<Payslip>> myPayslips({required int page, required int perPage}) async {
    _enter('myPayslips');
    final mine = [
      for (final slips in payslipsByRun.values)
        for (final slip in slips)
          if (slip.runStatus != PayrollRunStatus.draft) slip,
    ];

    return paginateFake(mine, page: page, perPage: perPage);
  }

  // -- helpers --------------------------------------------------------------

  Payslip _find(int payslipId) =>
      payslipsByRun.values.expand((slips) => slips).firstWhere((slip) => slip.id == payslipId);

  PayrollRun _runOf(Payslip slip) => storedRuns.firstWhere((run) => run.id == slip.payrollRunId);

  Payslip _replace(Payslip updated) {
    final slips = payslipsByRun[updated.payrollRunId]!;
    payslipsByRun[updated.payrollRunId] = [for (final slip in slips) slip.id == updated.id ? updated : slip];

    return updated;
  }

  void _setStatus(int runId, PayrollRunStatus status) {
    final index = storedRuns.indexWhere((r) => r.id == runId);
    final old = storedRuns[index];
    storedRuns[index] = _run(id: old.id, year: old.year, month: old.month, status: status);
    payslipsByRun[runId] = [
      for (final slip in payslipsByRun[runId]!)
        _payslip(slip.id, storedRuns[index], null, double.parse(slip.netPay), lines: slip.lines, from: slip),
    ];
  }

  PayrollRun _withTotals(PayrollRun run) {
    final slips = payslipsByRun[run.id] ?? [];
    final net = slips.fold<double>(0, (total, slip) => total + double.parse(slip.netPay));
    final paid = slips.where((slip) => slip.isPaid).length;

    return PayrollRun(
      id: run.id,
      schoolId: 1,
      schoolName: 'Sunrise Public School',
      year: run.year,
      month: run.month,
      periodLabel: run.periodLabel,
      status: run.status,
      currencyCode: 'INR',
      workingDays: 21,
      employees: slips.length,
      paidCount: paid,
      unpaidCount: slips.length - paid,
      grossTotal: net.toStringAsFixed(2),
      deductionsTotal: '0.00',
      netTotal: net.toStringAsFixed(2),
      missingSalaries: [
        if (run.status == PayrollRunStatus.draft)
          for (final employee in employees.where((e) => e.salary == null))
            MissingSalary(
              staffProfileId: employee.staffProfileId,
              employeeId: employee.employeeId,
              name: employee.name,
              reason: 'No salary has been set.',
            ),
      ],
    );
  }

  PayrollRun _run({required int id, required int year, required int month, required PayrollRunStatus status}) {
    const months = [
      'January',
      'February',
      'March',
      'April',
      'May',
      'June',
      'July',
      'August',
      'September',
      'October',
      'November',
      'December',
    ];

    return PayrollRun(
      id: id,
      schoolId: 1,
      schoolName: 'Sunrise Public School',
      year: year,
      month: month,
      periodLabel: '${months[month - 1]} $year',
      status: status,
      currencyCode: 'INR',
      workingDays: 21,
      employees: 0,
      paidCount: 0,
      unpaidCount: 0,
      grossTotal: '0.00',
      deductionsTotal: '0.00',
      netTotal: '0.00',
    );
  }

  Payslip _payslip(
    int id,
    PayrollRun run,
    EmployeeSalary? employee,
    double net, {
    List<PayslipLine>? lines,
    Payslip? from,
  }) {
    return Payslip(
      id: id,
      payrollRunId: run.id,
      periodLabel: run.periodLabel,
      runStatus: run.status,
      schoolName: 'Sunrise Public School',
      staffProfileId: from?.staffProfileId ?? employee!.staffProfileId,
      employeeName: from?.employeeName ?? employee!.name,
      employeeCode: from?.employeeCode ?? employee!.employeeId,
      currencyCode: 'INR',
      workingDays: 21,
      paidDays: 21,
      absentDays: 0,
      halfDays: 0,
      unmarkedDays: 21,
      grossEarnings: net.toStringAsFixed(2),
      totalDeductions: '0.00',
      netPay: (net < 0 ? 0 : net).toStringAsFixed(2),
      shortfall: (net < 0 ? -net : 0).toStringAsFixed(2),
      status: from?.status ?? PayslipStatus.unpaid,
      paidOn: from?.paidOn,
      paymentMode: from?.paymentMode,
      paymentReference: from?.paymentReference,
      lines:
          lines ??
          [
            PayslipLine(
              id: id * 10,
              type: PayComponentType.earning,
              name: 'Basic salary',
              amount: net.toStringAsFixed(2),
              fullAmount: net.toStringAsFixed(2),
              isAdjustment: false,
            ),
          ],
    );
  }

  Payslip _paid(Payslip slip, PaymentMode mode, String? reference) {
    return Payslip(
      id: slip.id,
      payrollRunId: slip.payrollRunId,
      periodLabel: slip.periodLabel,
      runStatus: slip.runStatus,
      schoolName: slip.schoolName,
      staffProfileId: slip.staffProfileId,
      employeeName: slip.employeeName,
      employeeCode: slip.employeeCode,
      currencyCode: slip.currencyCode,
      workingDays: slip.workingDays,
      paidDays: slip.paidDays,
      absentDays: slip.absentDays,
      halfDays: slip.halfDays,
      unmarkedDays: slip.unmarkedDays,
      grossEarnings: slip.grossEarnings,
      totalDeductions: slip.totalDeductions,
      netPay: slip.netPay,
      shortfall: slip.shortfall,
      status: PayslipStatus.paid,
      paidOn: '2026-09-30',
      paymentMode: mode,
      paymentReference: reference,
      lines: slip.lines,
    );
  }
}

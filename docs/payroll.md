# Payroll (Phase 19)

Monthly salaries for a school's employees: what each person is paid, a month's
run from draft to paid, payslips each employee can read, and an audit trail of
every change. Built on the Python backend only; Laravel's migrations still
create the tables, because they own the schema until the cutover
(`docs/python-migration.md`, the `queued_jobs` precedent).

There was no written specification. The rules below were decided by the
product owner on 2026-09-17, question by question; the few marked
*engineering choice* follow from those answers and are named so they can be
challenged.

```
FEATURE:        Payroll, and the Accountant role that runs it
OBJECTIVE:      Pay staff monthly from a salary structure, pro-rated by attendance,
                through a draft -> finalized -> paid run, with payslips and an audit trail
DATABASE:       audit_logs, salary_profiles, salary_components, payroll_runs, payslips, payslip_lines
API:            /payroll/salaries, /payroll/runs, /payroll/payslips, /payroll/my-payslips
FLUTTER:        Payroll (salary setup + runs + payslips), My Payslips, Accountant role everywhere
AUTHORIZATION:  ACCOUNTANT (own school), SCHOOL_ADMIN / GROUP_ADMIN (their scope): manage.
                SUPER_ADMIN: read only, any school. Every employee: their own final payslips
VALIDATION:     amounts >= 0 with 2dp, component names unique per salary, month not in the future,
                one run per school and month, state checks on every transition
BUSINESS RULES: below
TESTS:          ALLOW/DENY per endpoint and role, the pro-rating arithmetic, state transitions,
                PDF + email job, contract suite, Flutter unit/widget + an end-to-end accountant flow
DEPENDENCIES:   Teachers & Staff, Staff Attendance, Staff Leave (via the register), Holidays,
                School currency, the queue and mailer, Dashboard, Reports
```

## Who can do what

| | Accountant | School / Group Admin | Super Admin | Any employee |
|---|---|---|---|---|
| Set a salary | own school | their scope | - | - |
| Generate, adjust, regenerate, delete a draft run | own school | their scope | - | - |
| Finalize a run, mark payslips paid, email payslips | own school | their scope | - | - |
| Read salaries, runs, payslips | own school | their scope | every school | - |
| Read own payslips | yes | yes | - | finalized or paid only |

**The Accountant** is a seventh role, created from Teachers & Staff like a
Transport Manager, with a staff profile. Beyond payroll an Accountant is an
ordinary employee: they apply for leave, read the timetable and their inbox,
and appear on the staff register. They also read the staff attendance report,
the figures payroll is computed from. An Accountant belongs to exactly one
school; a group's accountant is an admin.

## Pay

- **Salary profile** per employee: a monthly **basic** plus named **earning**
  and **deduction** components, fixed amounts in the school's currency. No
  country-specific tax or statutory formulas - schools are multi-nation.
- **Paid days** for a month, over the school's working days (weekdays that are
  not holidays, `HolidayService.working_dates`):
  - present, or on leave (approved leave is written onto the register): 1
  - half day: 0.5
  - absent: 0
  - **no mark at all: 1** - a register nobody took never docks anybody's pay
  - a working day before the employee's joining date: 0 *(engineering choice)*
- **Everything is pro-rated**: basic, each earning and each deduction is
  `amount x paid days / working days`, rounded to 2 decimals half-up
  *(rounding: engineering choice)*. A month with no working day at all pays in
  full *(engineering choice)*.
- **Adjustments** are one-off named earning or deduction lines with a note,
  added to one employee's draft payslip for that month. Not pro-rated.
- **Net pay** = pro-rated earnings + earning adjustments - pro-rated deductions -
  deduction adjustments. It never goes below zero; a shortfall is shown on the
  payslip *(engineering choice)*.
- **Currency**: every money row carries `currency_code`, snapshotted from the
  school when the salary is set or the run generated (CLAUDE.md rule 5). A run
  has one currency - the school's.

## A month's run

```
generate --> DRAFT --(adjust / regenerate)--> DRAFT --finalize--> FINALIZED --pay all payslips--> PAID
               \--delete
```

- **Generate** for a school and a month that is not in the future; one run per
  school per month. Every active employee on the staff roster **with a salary
  profile** gets a payslip; employees without one are listed on the run as
  *missing a salary* so nobody is dropped silently.
- **Draft**: adjustments may be added and removed. **Regenerate** recomputes
  every payslip from the current salaries and register, adds newly eligible
  employees, drops ones no longer eligible, and keeps the adjustments of those
  who remain. A draft can be deleted.
- **Finalize** locks the run: no adjustment, regeneration or deletion after
  it. Each payslip's employee details, salary lines and day counts are
  snapshots, so later salary changes never rewrite a finalized payslip.
  Finalizing queues each employee's payslip email.
- **Pay**: each payslip is marked paid with a date, a mode (Cash, Bank
  Transfer, UPI, Cheque, Online Transfer) and an optional reference - one at a
  time or all unpaid at once. When every payslip is paid the run is **paid**.
- **Payslip PDF**: downloadable by whoever may read it, and emailed to the
  employee through the queue (`payslip_email` job), like payment receipts.

## Audit

`audit_logs` records who did what to which record, with old and new values and
the IP (CLAUDE.md §13). Built in this phase because payroll is its first
consumer; Phase 21 extends the same service to the other modules. Never logs a
password or token.

| action | entity | old / new |
|---|---|---|
| `salary.saved` | salary_profile | basic + components before / after |
| `payroll_run.generated`, `.regenerated`, `.deleted`, `.finalized`, `.paid` | payroll_run | status, totals |
| `payslip.adjustment_added`, `.adjustment_removed` | payslip | the line |
| `payslip.paid` | payslip | paid date, mode, reference |

## Tables

All created by Laravel migrations, `managed = False` in Django. Money is
`DECIMAL(12,2)` beside a `CHAR(3)` currency code. Timestamps as elsewhere.

### audit_logs
| column | type | notes |
|---|---|---|
| id | bigint pk | |
| school_id | fk schools, nullable, null on delete | null for platform actions |
| user_id | fk users, nullable, null on delete | the actor; null for the system |
| action | string(64) | e.g. `payroll_run.finalized` |
| module | string(32) | e.g. `payroll` |
| entity_type | string(64) | e.g. `payroll_run` |
| entity_id | bigint, nullable | |
| old_values, new_values | json, nullable | never secrets |
| ip | string(45), nullable | IPv6-sized |
| created_at | timestamp | append-only: no updated_at |

Indexes: (school_id, created_at), (entity_type, entity_id), (user_id).

### salary_profiles
One per employee. **Lifecycle:** created on first save, edited in place (each
save audited), deleted with the staff profile.

| column | type | notes |
|---|---|---|
| id | bigint pk | |
| school_id | fk schools, cascade | |
| staff_profile_id | fk staff_profiles, cascade, **unique** | |
| basic_salary | decimal(12,2) | monthly, >= 0 |
| currency_code | char(3) | school's currency when saved |
| updated_by | fk users, nullable, null on delete | |
| created_at, updated_at | timestamps | |

### salary_components
| column | type | notes |
|---|---|---|
| id | bigint pk | |
| salary_profile_id | fk salary_profiles, cascade | |
| type | string(16) | `earning` or `deduction` |
| name | string(100) | unique per profile and type |
| amount | decimal(12,2) | monthly, >= 0 |
| sort_order | smallint | display order |
| created_at, updated_at | timestamps | |

Unique: (salary_profile_id, type, name).

### payroll_runs
**Lifecycle:** draft -> finalized -> paid; only a draft may be deleted.

| column | type | notes |
|---|---|---|
| id | bigint pk | |
| school_id | fk schools, cascade | |
| year | smallint | |
| month | smallint | 1-12 |
| status | string(16) | `draft`, `finalized`, `paid` |
| currency_code | char(3) | school's currency when generated |
| working_days | smallint | the month's working days at generation |
| generated_by | fk users, nullable, null on delete | |
| finalized_by | fk users, nullable, null on delete | |
| finalized_at | timestamp, nullable | |
| paid_at | timestamp, nullable | when the last payslip was paid |
| created_at, updated_at | timestamps | |

Unique: (school_id, year, month). Index: status.

### payslips
A snapshot: nothing on it is re-derived after finalizing.

| column | type | notes |
|---|---|---|
| id | bigint pk | |
| payroll_run_id | fk payroll_runs, cascade | |
| school_id | fk schools, cascade | |
| staff_profile_id | fk staff_profiles, cascade | |
| employee_name | string(255) | snapshot |
| employee_code | string(30) | snapshot of employee_id |
| designation | string(100), nullable | snapshot |
| department_name | string(255), nullable | snapshot |
| currency_code | char(3) | |
| working_days | decimal(5,1) | |
| paid_days | decimal(5,1) | |
| absent_days | decimal(5,1) | |
| half_days | smallint | |
| unmarked_days | smallint | counted as paid |
| gross_earnings | decimal(12,2) | pro-rated basic + earnings + earning adjustments |
| total_deductions | decimal(12,2) | pro-rated deductions + deduction adjustments |
| net_pay | decimal(12,2) | never below zero |
| shortfall | decimal(12,2) | deductions beyond earnings, default 0 |
| status | string(16) | `unpaid`, `paid` |
| paid_on | date, nullable | |
| payment_mode | string(32), nullable | |
| payment_reference | string(100), nullable | |
| emailed_at | timestamp, nullable | |
| created_at, updated_at | timestamps | |

Unique: (payroll_run_id, staff_profile_id). Indexes: staff_profile_id, status.

### payslip_lines
| column | type | notes |
|---|---|---|
| id | bigint pk | |
| payslip_id | fk payslips, cascade | |
| type | string(16) | `earning` or `deduction` |
| source | string(16) | `basic`, `component`, `adjustment` |
| name | string(100) | |
| full_amount | decimal(12,2), nullable | the monthly figure before pro-rating; null for an adjustment |
| amount | decimal(12,2) | what is paid or deducted this month |
| note | string(255), nullable | required for an adjustment |
| sort_order | smallint | |
| created_by | fk users, nullable, null on delete | who added an adjustment |
| created_at, updated_at | timestamps | |

Index: payslip_id.

## Where the rest of the app changed

The Accountant is an employee first, so the role had to reach every place that
decides what an employee can do. A role list that forgot it would fail closed
(the accountant could not apply for leave) or, worse, open.

| Module | Change |
|---|---|
| Roles | `ACCOUNTANT` in the Python enum, Flutter's `UserRole`, and Laravel's enum (so Laravel can still read the user row) |
| Teachers & Staff | creatable from Add Staff, assignable by a school admin, counted as non-teaching on the roster, accepted by the staff importer |
| Leave | an accountant applies for leave and sees only their own. Leave scoping is now an allow-list: admins and the Super Admin see their scope, **every other role sees only its own** - a new role can no longer fall through to seeing everyone's |
| Staff attendance | the accountant is marked on the register like any employee, and those marks drive paid days |
| Holidays | the school's holidays take working days out of the month, exactly as in reports |
| Dashboard | an accountant gets payroll cards (this month's run, salaries not set, unpaid payslips) plus the employee leave and inbox cards; Laravel's dashboard treats the role as staff |
| Reports | the accountant may run the staff attendance report - the one that explains a payslip's days |
| Sidebar | Payroll for managers and the Super Admin (view only); My Payslips for every employee |
| Queue | finalizing queues one `payslip_email` job per payslip; the handler skips drafts and deactivated users |
| Audit log | new `audit_logs` table and `school/audit.py`; payroll is its first writer, Phase 21 adds the rest |
| Contract suite | payroll routes are listed as Python-only, and skipped when the suite runs against Laravel |
| Integration fixtures | `itest-accountant`, and `clean` removes payroll and audit rows |

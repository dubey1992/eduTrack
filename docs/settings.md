# Module settings and the permissions matrix

Decided with the user on 2026-09-19 and built on the Python backend and the
Flutter app only, like everything since Phase 19. Laravel still owns the
schema, so the two tables are Laravel migrations dated `2026_09_28`.

```
FEATURE: Module-wise settings; a roles & permissions matrix
OBJECTIVE: each module can be switched on or off per school and carries its
  own settings; the Super Admin edits one platform-wide matrix of what each
  role may do in each module, which every policy enforces
DATABASE: module_settings (school, module, platform_enabled, school_enabled,
  settings json), role_permissions (role, module, level)
API: GET settings/modules, PUT settings/modules/{module},
     GET/PUT settings/permissions, POST settings/permissions/reset;
     /me gains "modules" and "permissions"
FLUTTER: Module Settings screen (Super Admin and School Admin), Permissions
  screen (Super Admin edits, other admins read), sidebar and buttons gated by
  the matrix and the module switches
```

## Modules

A module is what a school sees as one thing in the sidebar. The registry is
`school/modules.py`; there is no table of modules, only of what a school has
changed.

| Module | Switchable | Own settings |
|---|---|---|
| Students, Teachers & Staff, Academic Set-up, Admin Users, Audit Log | no - the spine | - |
| Student Attendance | yes | days a register may be marked late (default 30; 0 = today only) |
| Staff Attendance | yes | days a register may be marked late (default 30) |
| Staff Leave | yes | minimum notice in days (default 0) |
| Timetable, Syllabus, HOD Reports, Transport, Announcements, Reports | yes | - |
| Teaching Reports | yes | days allowed to file a report (default 0 = no limit) |
| Communication | yes | - (Alert Settings hold the rest) |
| Payroll | yes | email payslips when a run is finalized (default on) |

**Two switches.** The platform grants a module to a school (Super Admin,
`platform_enabled`) and the school keeps it on (School Admin,
`school_enabled`). A module is on only when both say so; the platform
switch wins, and a School Admin who moves it gets a 422 naming the reason.
A school with no row has every module on with its default settings, so
nothing changes for existing schools until somebody edits something.

**Off means off everywhere.** Every policy asks `permitted()` first, which
refuses a switched-off module with `403 MODULE_DISABLED` and a sentence
naming the module - not the bare "not allowed" of a permission refusal. The
app reads `/me.modules` and hides the module's sidebar entries and buttons;
the API refuses regardless of what the app shows. Data is never deleted:
switching a module back on shows everything as it was.

Two consequences worth knowing:
- Communication off records nothing at all - no alert, no "skipped" row -
  like an alert the school switched off.
- Approving leave still writes the attendance it always wrote, whether or
  not the attendance module is on; the record has to be right when the
  module comes back.

**Every setting does something.** A setting nothing reads would be a lie on
a screen, so each one is enforced in the service it belongs to and refused
with `422 SETTING_REFUSED` and its own sentence: "Attendance can only be
marked for today or the last 3 days.", "Leave must be applied for at least 7
days in advance.", "A report can only be filed up to 1 day after the
period." Settings are declared with a type and a range, and the API refuses
anything else by name.

## The permissions matrix

One matrix for the whole platform: role by module, each cell **none**,
**view** or **manage**. The Super Admin edits it; every administrator can
read it, so a School Admin can see what their staff may do.

| | School Admin | HOD | Teacher | Staff | Transport | Accountant |
|---|---|---|---|---|---|---|
| Students | manage | none | view | none | none | none |
| Teachers & Staff | manage | none | none | none | none | none |
| Academic Set-up | manage | view | view | view | view | view |
| Student Attendance | manage | none | manage | none | none | none |
| Staff Attendance | manage | manage | none | none | none | none |
| Staff Leave | manage | manage | manage | manage | manage | manage |
| Timetable | manage | view | view | view | view | view |
| Teaching Reports | manage | manage | manage | none | none | none |
| Syllabus | manage | manage | manage | none | none | none |
| HOD Reports | view | view | none | none | none | none |
| Transport | manage | view | view | none | manage | none |
| Communication | manage | none | none | none | none | none |
| Announcements | manage | manage | none | none | none | none |
| Payroll | manage | none | none | none | none | manage |
| Reports | view | view | none | none | view | view |

These defaults are exactly what the policies allowed before the matrix
existed, which is why the whole test suite passes with an empty matrix.
Only cells that differ from a default are stored, so "reset to defaults"
is deleting them. Every change is in the audit trail as
`permission.changed`, with the old and new level.

**The matrix decides whether; the policies decide whose.** Raising a role
widens what it may do, never whose records it reaches:

- A teacher raised to *manage* students may add a student, and still reads
  and edits only the sections they are the class teacher of.
- A head of department raised to *manage* announcements publishes to their
  own department, as before.
- *Manage* on leave means applying for your own; reviewing somebody else's
  stays with administrators and the applicant's head of department.
- *View* on reports never adds a report a role was not a reader of - a
  payroll summary stays with those who run payroll.
- Transport *manage* runs trips; the fleet itself stays with administrators.

Not in the matrix: **Super Admin** (always full, never editable), **Group
Admin** (follows the School Admin row, as it does everywhere), and the
platform's own business - schools, payments, mail settings, admin users and
the audit log - whose policies answer for themselves.

**Order of checks.** A switched-off module is refused before the matrix is
consulted, so a role with *manage* still gets `MODULE_DISABLED` when the
school has the module off.

## What the app does with it

`/me` (and sign-in) carry `permissions` - every module's level for this
account - and `modules` - whether each module is on for their school. The
sidebar shows a module's entries only when the module is on and the level
is at least *view*; buttons that write need *manage*. A stale app that
tries anyway meets the API's refusal, and a `MODULE_DISABLED` answer is
shown as "switched off for your school" rather than as an error.

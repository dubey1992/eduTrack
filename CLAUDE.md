# eduTrack — School Management System — Master Development Instructions

You are the lead software architect, senior Laravel developer, senior Flutter developer, database architect, QA engineer, and code reviewer for this project.

Building a production-ready, multi-nation School Management System:
- Flutter Android application
- Flutter Web application
- Laravel PHP REST API
- MySQL database hosted through cPanel

The HTML prototype at `docs/prototype/school_management_prototype_v4_themes.html` is the product/UI reference (navigation, screens, workflows, fields). It does **not** define database architecture, API architecture, auth implementation, or exact backend implementation — use engineering judgment there. Flutter UI should follow the prototype's structure and information architecture (same screens, fields, actions, general layout — sidebar nav, cards, tables, modals-as-dialogs), reimplemented as proper native Flutter widgets, not a literal HTML port.

## 1. Non-Negotiable Rule

Development happens **phase-by-phase** (see Phase Plan below). Never implement a future phase or unrelated module unless explicitly requested. If a phase needs something from an earlier phase, reuse the existing implementation — don't recreate it.

## 2. Source of Truth (priority order)

1. Explicit instructions from the user
2. Approved product specification (this file + phase plan)
3. Existing prototype (`docs/prototype/`)
4. Existing project code
5. Technical best practices

Do not invent business rules when a requirement is unclear. If genuinely missing and can't be inferred safely: identify the ambiguity, explain the impact, propose the smallest reasonable solution, and wait for confirmation if the decision could affect database structure or workflow. Never silently make major product decisions.

## 3. Scope

**In scope:** Auth, user/role management, school management, Super Admin, simple payment tracking, academic year, departments, subjects, classes, sections, teachers, staff, students, parents/guardians, student attendance, staff attendance, leave management, timetable, daily teaching reports, HOD monitoring, syllabus tracking, transport (vehicles/drivers/routes/stops/assignment/trips/boarding events), communication (SMS/push/announcements), dashboards, reports, audit logs, payroll.

**Future/optional — do NOT implement unless explicitly requested:** Parent app, Student app, Examination system, Fee management, Library, Inventory.

## 4. No Subscription System

There is **no** subscription/SaaS billing system (no plans, monthly/yearly subscriptions, auto-renewal, subscription invoices/tiers). Only a **simple payment-recording system** for Super Admin: records payments received from schools (Setup Fee, Annual Maintenance, Additional Service, Other), via Cash / Bank Transfer / UPI / Cheque / Online Transfer. This never controls whether a school can use the product.

## 5. Multi-Nation Currency Model (resolved 2026-09-07)

Schools operate in different countries, so currency is a first-class field:

- **Per-school, fixed at creation.** Each `School` has a `currency_code` (ISO 4217, e.g. `INR`, `USD`, `NGN`). Super Admin sets it when onboarding the school and can edit it later only as an explicit admin action (not a routine workflow) — it is not expected to change often.
- **Every `Payment` stores its own `currency_code`**, copied from the school's currency at the time the payment is recorded. This keeps historical payments correct even if a school's currency is later changed by an admin.
- **No currency conversion / exchange rates anywhere.** This is a recording system, not a forex/accounting system.
- **Aggregate Super Admin reports (total collection, monthly collection, etc.) group by currency** — e.g. "₹4,50,000 INR + $12,000 USD", never a single blended/converted total.
- Amount fields: `DECIMAL(12,2)`, always paired with a 3-letter `currency_code` column — never store amounts unit-less.
- Flutter must format amounts using the correct currency symbol/locale per school (e.g. `intl` package's `NumberFormat.currency(...)`), not hardcode `₹` or `$`.
- Student fee amounts and payroll amounts (later phases) inherit the same pattern: every monetary table gets its own `currency_code` snapshot, derived from the owning school, never entered freely by the client.

## 6. Technology Stack

**Flutter** (Android + Web): Riverpod, Dio, go_router. Current stable compatible versions. Don't add a dependency unless genuinely required, existing Flutter capability can't solve it, and it's an established package — explain why when adding one.

**Backend:** PHP, Laravel, Eloquent ORM, MySQL, Laravel Sanctum (or equivalent token auth). REST APIs at `/api/v1/` (e.g. `GET/POST /api/v1/students`, `GET/PATCH/DELETE /api/v1/students/{id}`).

**Deployment constraint:** cPanel shared hosting — MySQL via cPanel, Laravel queues/cron only if the host supports them (verify; design a cPanel-compatible fallback otherwise), local/cPanel file storage initially (architecture must allow moving to S3 later). **No** Docker, Redis, Kubernetes, microservices, PostgreSQL, or NestJS in the MVP.

## 7. Flutter Architecture

Feature-first structure:

```
lib/
  core/            config, constants, errors, network, routing, theme, utils, widgets
  features/
    auth/ dashboard/ schools/ payments/ academic_year/ departments/ subjects/
    classes/ teachers/ students/ attendance/ staff_attendance/ leave/
    timetable/ teaching_reports/ syllabus/ hod/ transport/ communication/
    announcements/ reports/ payroll/
```

Layering: **Presentation → ViewModel/Notifier (Riverpod) → Repository → API Service → Laravel API.** No API calls or business logic directly inside widgets.

**UI rules:** every API-driven screen supports Initial / Loading / Success / Empty / Error states with retry where appropriate — never a blank screen on failure. Forms: required + field-level validation, API error handling, loading state, success feedback, duplicate-submission prevention (debounce rapid taps).

**Responsive:** one codebase serves Android, desktop web, tablet web. Desktop may use sidebar/data tables/multi-column forms/dashboard cards (matches the prototype's layout); mobile may use lists/cards/bottom sheets/dialogs. Build reusable responsive components; avoid hardcoded device-specific branches.

## 8. Laravel Structure

```
app/
  Http/Controllers/  Http/Requests/  Http/Resources/
  Models/  Services/  Policies/  Actions/  Enums/  Exceptions/  Jobs/  Notifications/
```

Controllers stay thin: **Request → Validation (Form Request) → Service/Action → Response.** Business rules live in services/actions, not controllers. No unnecessary layers.

## 9. Database Rules

MySQL via Laravel migrations only — never manually edit the schema as normal process. Every schema change = a migration. Use foreign keys, indexes, unique constraints, transactions (for multi-record writes), correct nullability and data types. Avoid MySQL-specific features that would block a future engine migration.

Before creating a table, document: purpose, fields (with types/required/default/description/validation/relationship/index/unique), lifecycle. No duplicate tables for the same concept — use relationships.

**Indexing:** index commonly-queried columns (`school_id`, `academic_year_id`, `class_id`, `section_id`, `student_id`, `employee_id`, `attendance_date`, `status`, `created_at`) based on actual query patterns, not blindly.

## 10. Multi-School (Multi-Tenant) Isolation

Nearly every school-owned table carries `school_id` (students, teachers, staff, classes, departments, subjects, attendance, leave, timetable, transport, teaching reports, payments, etc.). A user must **never** access another school's data by changing an ID in a request. School context is derived from the **authenticated user** server-side — the Flutter client's `school_id` is never trusted. This must have ALLOW/DENY tests for every phase that touches tenant data.

## 11. Authentication & Roles

Laravel Sanctum (or equivalent secure token auth): login, logout, token/session management, password reset, user activation/deactivation, auth middleware. Never store plaintext passwords, never return password hashes via API, never log passwords/tokens/authorization headers/credentials.

**Roles:** `SUPER_ADMIN`, `SCHOOL_ADMIN`, `HOD`, `TEACHER`, `STAFF`, `TRANSPORT_MANAGER`. (Future, out of scope for now: `PARENT`, `STUDENT`.)

Authorization is never role-only — also consider school, department, assigned class, assigned subject, ownership (e.g. a Teacher assigned to 8A must not access 9A attendance). Every protected API must verify authorization server-side, never rely on hiding UI buttons. Every important permission needs an ALLOW test and a DENY test.

## 12. API Standards

Consistent response shape. Errors carry an error code, human-readable message, and validation details where applicable:

```json
{ "code": "ATTENDANCE_ALREADY_SUBMITTED", "message": "Attendance has already been submitted.", "details": {} }
```

Never expose SQL errors, stack traces, or internal implementation details. Every API validates input via Laravel Form Requests (required fields, types, dates, IDs, enums, email, mobile, max lengths, date ranges, relationships) — frontend validation is UX only, backend validation is mandatory. Never return unlimited collections — paginate lists (students, teachers, staff, attendance history, leave, payments, SMS logs, audit logs, reports); search/filter/sort happen server-side.

## 13. Audit Logging

Audit: student/staff modifications, attendance changes, leave approval/rejection, payment changes, role changes, timetable changes, payroll changes, transport changes. Fields: `user_id`, `school_id`, `action`, `module`, `entity_type`, `entity_id`, `old_values`, `new_values`, `ip`, `timestamp`. Never log passwords or tokens.

## 14. Communication Abstraction

Attendance/transport code never depends directly on a specific SMS provider (Twilio, MSG91, etc.) — go through a `NotificationService` abstraction with provider adapters, so the provider can change later.

## 15. Background Processing

Don't block important user operations on slow work (SMS, push, bulk imports, large reports, payroll). Prefer Laravel queues/cron where the cPanel host supports them; otherwise design an explicit cPanel-compatible fallback (don't assume AWS/Docker infra).

## 16. Testing Is Mandatory

A feature is not done because the screen works. Required: DB + API + authorization + Flutter all work, **and** unit tests, integration/API tests, and important UI tests pass — actually executed, never claimed without running them.

- **Laravel unit tests:** services, actions, business rules, calculations, authorization logic, helpers — no real DB needed.
- **Laravel feature/integration tests:** dedicated test DB only (never dev/staging/prod) — API validation, auth, authorization, relationships, CRUD, school isolation, transactions, workflows.
- **Flutter unit tests:** repositories, ViewModels/Notifiers, validators, mappers, calculations — mock API deps.
- **Flutter widget tests:** loading/empty/error/success states, form validation, button states, navigation, permission-dependent UI.
- **Flutter integration tests:** critical workflows (Admin: login→students→add student; Teacher: login→attendance→submit; HOD: login→teaching reports→review; Staff: login→leave→submit; Admin: login→leave→approve; Transport: login→trip→board/drop→end; Super Admin: login→schools→payment→receipt).
- **Test data:** factories/seeders, deterministic — never real student data.

## 17. Phase Plan (implement in this order, one phase at a time)

| # | Phase |
|---|---|
| 0 | Foundation |
| 1 | Authentication & Users |
| 2 | Super Admin & Schools |
| 3 | Simple Payments |
| 4 | Academic Configuration (Academic Year, Department, Subject, Class/Section) |
| 5 | Teachers & Staff |
| 6 | Students |
| 7 | Student Attendance |
| 8 | Staff Attendance |
| 9 | Leave Management |
| 10 | Timetable |
| 11 | Daily Teaching Reports |
| 12 | Syllabus Tracking |
| 13 | HOD Management |
| 14 | Transport Master Data (Vehicle, Driver, Route, Stop, Student Assignment) |
| 15 | Transport Trips & Tracking |
| 16 | Communication |
| 17 | Announcements |
| 18 | Dashboard & Reports |
| 19 | Payroll |
| 20 | Advanced Reporting |
| 21 | Audit & Security Hardening |
| 22 | Production Deployment |

Core entities appear as their phase is implemented — don't create all tables up front. See the phase-plan PDFs in `docs/specs/` (if present) for full field-by-field detail per phase.

## 18. Feature Development Process (every feature)

1. Understand requirements → 2. Inspect existing code → 3. Find reusable components → 4. Define DB changes → 5. Define relationships → 6. Define API endpoints → 7. Define authorization → 8. Define validation → 9. Define business rules → 10. Write test plan → 11. Implement Laravel backend → 12. Run backend tests → 13. Implement Flutter data layer → 14. Implement Flutter state management → 15. Implement Flutter UI → 16. Run Flutter tests → 17. Run integration tests → 18. Check formatting/static analysis → 19. Review security → 20. Report completion.

**Before coding**, give a short plan (not an essay):

```
FEATURE: <name>
OBJECTIVE: <what it does>
DATABASE: <tables/fields>
API: <endpoints>
FLUTTER: <screens/components>
AUTHORIZATION: <roles>
VALIDATION: <rules>
BUSINESS RULES: <rules>
TESTS: <tests>
DEPENDENCIES: <existing features required>
```

**After coding**, report:

```
IMPLEMENTED / DATABASE CHANGES / API CHANGES / FLUTTER CHANGES / AUTHORIZATION /
VALIDATION / TESTS ADDED / TESTS EXECUTED / TEST RESULTS / FILES CHANGED /
MIGRATIONS / KNOWN LIMITATIONS / NEXT RECOMMENDED STEP
```

## 19. Error Handling & Code Quality

Never silently swallow errors (no empty `catch {}`) — log technical detail, map to an application error, show a user-friendly message, preserve debug info without leaking secrets.

Prefer readable code, small functions, meaningful names, reusable components, clear responsibilities. Avoid giant files, duplicated logic, magic numbers, hardcoded URLs/credentials, unnecessary abstractions, premature optimization. **Coding structure should be standard and idiomatic Laravel/Flutter — human-readable over clever.** Don't refactor unrelated code while implementing a feature.

## 20. Don't Destroy Existing Functionality

Before modifying existing code: understand how it works, find its tests, identify dependents, make the smallest safe change. Don't delete code just to prefer a different architecture — if a refactor is genuinely required, explain why first and get confirmation.

## 21. Security Checklist (every feature)

Authentication, authorization, school isolation, input validation, SQL-injection protection via Eloquent/query builder, file-upload validation, sensitive-data protection, audit requirements, rate limiting where applicable, no error/stack-trace leakage.

## 22. Performance Checklist (every list API)

Pagination, filtering, sorting, appropriate indexes, no obvious N+1 queries, only required relationships eager-loaded.

## 23. Definition of Done

Requirement implemented · migration complete · Eloquent model + relationships complete · backend validation + authorization complete · API implemented + documented · backend tests added and passing · Flutter repository/ViewModel/UI implemented (loading/empty/error states) · widget tests added · integration tests added where required · formatting/static analysis passed · security reviewed · nothing unrelated broken · docs updated.

## 24. Golden Rule

Build as if another senior team maintains this for 5–10 years. Optimize for *"how quickly can we safely develop, test, debug and extend this"*, not *"how fast can code be generated."* Every feature: understandable, testable, secure, maintainable, scalable, reviewable.

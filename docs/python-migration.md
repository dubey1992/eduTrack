# Migrating to Python and PostgreSQL

**Status: M1 complete, M2 next.** Decided to proceed on 2026-09-16.

| Phase | |
|---|---|
| M0 Decisions | Partly answered — see below |
| M1 PostgreSQL locally, schema parity | **Done** 2026-09-16 |
| M2 Portability fixes | In progress |
| M3 onwards | Not started |

**Answered at M0:** Django + DRF is the framework. **Still open: whether the
host can run any of this** — nobody has asked the provider yet, and phases M5
and M12 cannot happen until somebody does.

Replacing the Laravel/PHP backend with Python, and MySQL with PostgreSQL, on a
system that already has a school using it in production.

CLAUDE.md §6 names PHP, Laravel and MySQL, and explicitly excludes PostgreSQL.
This document supersedes that section once Phase M1 lands; until then §6 still
describes what is actually running.

## The shape of it

These are **two independent migrations**, and the entire plan turns on keeping
them apart.

| | Effort | Reversible? |
|---|---|---|
| MySQL → PostgreSQL, still on Laravel | ~2 weeks | Yes, trivially |
| PHP/Laravel → Python | 4–7 months (one dev) | No |

The database move can be done first, on the backend that exists, proven by the
851 tests that already exist. Doing both at once means a broken report tells you
nothing about which change broke it.

So the phases below run in three tracks, in order: **get to Postgres** (M0–M5),
**freeze the contract** (M6), **replace the language** (M7–M12).

## What is being moved

Measured at commit `14acaf8`, not estimated.

| | |
|---|---|
| Application code | 19,111 lines, 302 files |
| Backend tests | 14,317 lines, 47 files, **851 passing** |
| REST endpoints | 153 (64 GET, 38 POST, 32 PATCH, 16 DELETE, 3 PUT) |
| Tables | 31 domain + 8 framework |
| Models / Services / Policies | 32 / 46 / 25 |
| Form Requests / Resources / Enums | 65 / 32 / 26 |
| Migrations / Factories | 43 / 31 |

**Not being moved, and this matters:** the Flutter apps. 27 API clients, 134
call sites, 705 tests, unchanged — *provided* the new backend reproduces the
existing contract exactly. That proviso is what Phase M6 exists to enforce.

## The rules this migration runs under

These are the things that make it safe rather than fast. They are not
negotiable mid-project, because every one of them exists to keep a step
reversible.

1. **The API contract never changes.** Not a field name, not a status code, not
   the `{code, message, details}` error envelope, not the `{data, meta}`
   pagination shape. If the Python backend wants a different shape, it is
   wrong. Improvements to the contract happen after the migration, never
   during it — a change of implementation and a change of behaviour must never
   arrive in the same commit.
2. **Both backends stay runnable** until the rollback window closes. The PHP
   app is not deleted, not archived, not "cleaned up".
3. **Every phase ends at something demonstrable**, and the phases marked
   **GATE** end at a decision. Reaching a gate and finding the answer is no
   should stop the project cheaply, which is the whole point of putting them
   early.
4. **No phase touches production** except M5 and M12, and both have a written
   rollback.
5. **The pilot school's data is never the test subject.** Migrations are
   rehearsed on a copy, every time.

---

# Track 1 — Get to PostgreSQL

Still Laravel. Everything here is covered by the 851 tests already written,
which is what makes it cheap.

## M0 · Decisions and host verification — **GATE**

No code. Four questions, and the project does not start until they are
answered.

**1. Can the host run it?** Production is cPanel shared hosting
(`eternal.herosite.pro`); `docs/deployment.md` assumes PHP 8.3, MySQL 8 and
cron. Ask the provider two things:

- Does this plan offer **PostgreSQL**? Many shared cPanel plans do not.
- Does it support a **Python application** under Passenger, with a persistent
  process and enough memory?

If either answer is no, the real decision is not a language — it is moving to a
VPS, which changes more about operations than the rewrite does.

**2. Why Python?** The answer changes the plan. "The team knows Python and not
PHP" points at the full rewrite. "We want analytics or ML later" is answered far
more cheaply by a Python service alongside the existing API (see *The cheaper
alternative* at the end).

**3. What happens to feature work?** Either it freezes for the duration, or
every new feature is built twice, in both stacks. Both are survivable. Drifting
into the second by accident is not.

**4. Django or FastAPI?** Recommendation: **Django + DRF**, reasoned below.

**Done when:** all four have written answers.

## M1 · PostgreSQL running locally, schema parity

**Work**

- Enable the driver — `php_pdo_pgsql.dll` already ships with the PHP install,
  commented out at `php.ini:957`. Two characters.
- Install PostgreSQL 16 locally alongside MySQL, on its own port, so the
  existing MySQL dev database is never at risk.
- Add a `pgsql` connection and a `.env.pgsql` so both can be run side by side.
- Run the 43 migrations against an empty Postgres database and diff the
  resulting schema against MySQL's, column by column.

**Done when:** `php artisan migrate:fresh` completes on Postgres and the schema
diff is understood line for line — every difference either intended or fixed.

**Rollback:** delete a database. Nothing shared is touched.

### What happened — 2026-09-16

**Done, and it went better than the plan assumed.** All 43 migrations ran on
PostgreSQL 16.8 **unchanged** — not one needed editing — and `schema:diff`
reports **0 differences across 40 tables and 399 columns**.

Set up, all of it outside the repo except the start script:

- PostgreSQL 16.8 as plain binaries at `C:\devtools\pgsql`, data at
  `C:\devtools\pgsql-data`, **port 5433**. No installer and no Windows
  service, matching how MySQL is set up on this machine.
- `scripts/start-postgres.ps1`, alongside `start-mysql.ps1`.
- `pdo_pgsql` and `pgsql` enabled in `php.ini` (they ship with the PHP build,
  commented out). Backup at `php.ini.bak-pre-pgsql`.
- The `pgsql` connection in `config/database.php` now reads **`PG_*`** env keys
  rather than the shared `DB_*` ones, so both databases are configured at once
  and the suite can be pointed at either without editing `.env`.
- `php artisan schema:diff` — the tool that proves parity, kept because M3 and
  M4 both have to make the same claim again.

Three things worth knowing for anyone repeating this:

- **The binaries zip needs `bin` on `PATH`**, not just a full path to
  `pg_ctl`. The postmaster starts fine without it and then every backend
  process dies with `0xC0000142` the moment something connects, which reads as
  a client problem and is not one.
- **PowerShell 5.1's `-Encoding utf8` writes a BOM**, and PostgreSQL refuses to
  parse `pg_hba.conf` with one — `invalid connection type "ï»¿"`.
- **`pg_ctl start` stays attached to the shell that ran it**, so the server
  dies with any script that starts it. The start script uses `Start-Process`,
  the same way `start-mysql.ps1` does.

**Collation was chosen, not inherited.** The cluster uses the **ICU** provider
with the locale-independent `und` collation and UTF-8 encoding, rather than a
Windows system locale. A multi-nation product should not sort Nigerian and
Indian school names differently depending on what the server's OS was
configured with.

## M2 · Portability fixes, still green on MySQL

Every change here is written so it is correct on **both** databases. This is
what keeps M1–M5 reversible: at no point is there a commit that only works on
Postgres.

**The four real differences found in this codebase.** The generic list is long;
these are the ones that actually apply. Worth stating first what is *not* a
problem: there are **no `enum` columns and no `json` columns**, all 21 raw-SQL
fragments are ordinary `SUM`/`COUNT`/`CASE WHEN` aggregates, and MySQL here
already runs with `ONLY_FULL_GROUP_BY`, so the strict-GROUP-BY difference that
usually bites is already satisfied.

### The baseline — 2026-09-16

Before changing anything, the whole suite was run against PostgreSQL to find
out what actually breaks rather than what was predicted to:

**845 of 851 passed.** Six failures, all one cause, and **not one of the four
differences listed below** — which is the point worth remembering. Those four
are *silent*: they change what the application returns without failing a test,
which is exactly why they need looking for rather than waiting for.

The six were `lockForUpdate()->count()` in `TransportTripService`, which
compiles to `SELECT count(*) ... FOR UPDATE`. MySQL accepts it; PostgreSQL
rejects it outright — *"FOR UPDATE is not allowed with aggregate functions"*.
Fixed by locking the rider rows and counting what came back, which states the
intent better on both: it is those rows that must hold still, and a lock on an
aggregate names none of them.

### Search stops being case-insensitive — 14 call sites

MySQL's collation makes `like` case-insensitive; Postgres's does not. Searching
`abhishek` would silently stop finding *Abhishek*, across students, staff,
announcements, messages and early-access requests. No error, no failing test.

**Fix:** one helper that picks `like` or `ilike` from the connection driver, used
at all 14 sites, plus a test that searches in deliberately the wrong case so the
regression cannot return.

### Email uniqueness stops being case-insensitive — `users.email`

Today `Head@school.com` and `head@school.com` cannot both exist. Under Postgres
they can — two accounts for one person, one of them unreachable by whoever
types the other spelling. This is an authentication boundary quietly changing
meaning, so it is the one to get right first.

**Fix:** normalise to lowercase on write, and a unique index on `lower(email)`.
**Check the pilot data for existing collisions before the import, not after.**

### Timestamps and per-school timezones — 17 timestamp, 14 date columns

eduTrack pins `APP_TIMEZONE` to UTC and resolves each school's local day in
application code (`docs/timezones.md`). Choose `timestamptz` carelessly and
Postgres shifts values by the session timezone on read, moving attendance
across a day boundary for any school far enough east or west.

**Fix:** decide per column, deliberately, and write the decision down. Pin the
connection timezone to UTC. The date/instant distinction is already load-bearing
here and must survive intact.

### Booleans and unsigned integers — 7 boolean columns, 87 keys

MySQL stores booleans as `tinyint(1)`, so a naive dump hands Postgres `0`/`1`
where it wants `true`/`false`. Postgres has no unsigned integers — `bigint`
holds every value, but the "cannot be negative" guarantee moves out of the
database and into application code.

**Fix:** use `pgloader` rather than a hand-rolled dump-and-load; it handles both.

**Done when:** 851 tests still green on MySQL, with every fix in place.

## M3 · Data migration rehearsal

**Work**

- A repeatable, scripted import: `pgloader` for structure and bulk data, then a
  verification pass.
- **Reset every sequence.** Postgres does not advance a sequence when a row is
  inserted with an explicit id. Import the pilot data with its keys intact and
  every sequence sits at 1 — the first student admitted after cutover collides
  with student #1 and the insert fails. It looks like total corruption and it is
  thirty seconds of SQL. `setval()` on every table, asserted rather than trusted.
- A verification script: row counts per table, and checksums on the tables where
  silence would be expensive — `attendances`, `staff_attendances`, `payments`,
  `students`, `users`.

**Done when:** the import has been performed **at least twice, from scratch,
on a copy of the pilot database**, and the verification script passes both
times with no manual steps.

**Rollback:** it is a copy.

## M4 · Both databases in CI

**Work:** the test suite runs against MySQL *and* Postgres on every commit.

**Done when:** 851 × 2 green. This is the phase that makes the rest of the
project safe, because from here on any behavioural difference between the two
databases fails a test rather than reaching a school.

## M5 · Production moves to PostgreSQL — *still Laravel*

The first phase that touches production. Small, well-rehearsed, and reversible
within minutes.

**Work:** maintenance page up (`php artisan down` — the custom page already
exists), final export, import, sequence reset, verification script, maintenance
page down.

**Done when:** the pilot school is working on Postgres and the verification
script has passed against production.

**Rollback:** point `.env` back at MySQL, which is still there, still current as
of the export, and untouched. Minutes, not hours.

**At this point the database migration is complete and the Python decision is
still entirely open.** If the project stops here it has still been worth doing.

---

# Track 2 — The safety rail

## M6 · Freeze the contract

The single most valuable artefact in this project, and the reason the Flutter
apps never have to change.

**Work:** capture all 153 endpoints as executable contract tests that run
against *any* backend over HTTP — request in, status code and JSON shape out.
Not Laravel tests: an external suite that knows only a base URL.

Each endpoint gets, at minimum: the success shape, the 404, the validation
failure envelope, and — for every endpoint that touches tenant data — the
ALLOW and the DENY (CLAUDE.md §10, §11). The 25 policies are where a rewrite
does its real damage, and this is what catches it.

**Done when:** the suite passes against the Laravel backend. From here it is the
definition of done for every Python module that follows.

---

# Track 3 — Replace the language

## Why Django + DRF, not FastAPI

Both are good frameworks. For *this* codebase the answer is not close. Look at
what the inventory is made of: 65 validators, 32 output shapes, 25 authorization
rules, 43 migrations, a token login. That list is a description of what Django
and DRF ship in the box.

FastAPI would mean assembling SQLAlchemy, Alembic, Pydantic and a permission
layer by hand — more code to write and more code to get wrong, in exchange for
async I/O that a school ERP's workload will never notice. The hot path here is a
paginated query with a tenant filter on it, not concurrency.

| Laravel | Count | Django / DRF | Notes |
|---|---|---|---|
| Services | 46 | plain modules | Easiest — already framework-light; the business rules move almost literally |
| Enums | 26 | `TextChoices` | Mechanical |
| Models | 32 | Django models | Must match the existing schema exactly, not generate a new one |
| API Resources | 32 | serializers | Mechanical, but every field name is a contract |
| Form Requests | 65 | serializers | The bulk of the tedium |
| Policies | 25 | permission classes | **The dangerous part** — every mistake is one school reading another's records |
| Controllers | 35 | viewsets | Thin by design, so thin to rewrite |
| Migrations | 43 | Django migrations | Written once against the live schema |
| Factories | 31 | `factory_boy` | Needed before any test can be written |
| Jobs | 3 | Celery or cron commands | Depends entirely on M0's hosting answer |
| Sanctum | — | DRF token auth | See the cutover note in M12 |

`SchoolScope` — the one class answering "which schools may this actor touch?" —
becomes one Python class of about the same size. It is the single most important
file in the migration.

## M7 · Skeleton

**Work:** Django + DRF project structure, settings, the 32 models written
against the **existing** schema (`inspectdb` as a starting point, then written
properly by hand), `factory_boy` factories, and the test harness. No endpoints.

**Done when:** the models round-trip every table, and the factories can build a
school with branches, staff and students.

## M8 · Auth, tenancy, and one module — **GATE**

The riskiest tenth of the system, deliberately done first and alone.

**Work:** login and token auth, the role model including `GROUP_ADMIN`,
`SchoolScope` and its unit tests, the school-group rules (`docs/branches.md`),
and **Students** end to end — list, create, update, deactivate, bulk import.

**Done when:** the Flutter app, unmodified, logs in against Python and manages
students; the contract tests for those endpoints pass; and every ALLOW/DENY
isolation test passes.

**This is the gate that matters.** If it has been miserable, stop here having
spent a month rather than six. The remaining modules are more of the same work —
if this was painful, the rest will be too, and that is worth knowing now.

## M9 · Wave 1 — foundations

Schools, school groups, payments, users and admin accounts, academic years,
departments, subjects, classes and sections, holidays, periods.

Ported in dependency order, because everything downstream references them.

**Done when:** each module's contract tests pass and its ALLOW/DENY tests exist.

## M10 · Wave 2 — people and daily operations

Teachers and staff, student attendance, staff attendance, leave management,
timetable.

The highest-traffic part of the product and the part a school notices within
minutes if it is wrong.

## M11 · Wave 3 — derived and outbound

Daily teaching reports, syllabus tracking, HOD monitoring, transport (master
data and trips), communication, announcements, early access, dashboards and the
four reports.

Reports last, on purpose: they read from everything above, so they are the
broadest end-to-end proof that the port is faithful. The per-branch group
reporting rules in `docs/reports.md` and `docs/branches.md` are the subtlest
arithmetic in the system — combined rates are recomputed from raw counts, never
averaged — and must be ported with their tests, not re-derived.

**Done when:** 153 of 153 endpoints answer identically, and the Flutter suite of
705 tests passes against the Python backend.

## M12 · Cutover and decommission

**Everyone is signed out.** Sanctum's `personal_access_tokens` hashes cannot be
validated by any Python auth. Every signed-in user at the pilot school is logged
out the moment you cut over — fine at 6am on a Saturday, a disaster at 9am on a
Monday while attendance is being marked. This is a planned consequence, not an
incident: schedule it outside school hours and tell the school beforehand that
they will need to sign in again.

**Work:** maintenance page, final data sync, document root or DNS switched,
sequences reset and asserted, smoke test as a real user of the pilot school.

**Rollback:** the PHP app stays deployed and the old database stays readable for
a fortnight. Reverting is a document-root switch.

**Decommission** only after that window passes without incident.

---

## Effort

**4–7 months for one experienced Python developer; 2.5–4 for two** who can split
along module lines from M9.

The range is honest rather than hedged: it depends almost entirely on M0's
hosting answer and on whether feature work is frozen. A single new feature built
twice, in both stacks, is the fastest way to double the number.

## What could go wrong, in order of likelihood

1. **The host cannot run Python or Postgres.** Most likely, and cheapest to
   discover — which is why it is M0 and not M7.
2. **A policy is ported subtly wrong** and one school can read another's data.
   The contract tests in M6 and the ALLOW/DENY pairs are the whole defence.
3. **Feature work does not actually freeze.** Everything gets built twice and
   the timeline doubles.
4. **The rewrite is abandoned half-finished**, leaving two backends to maintain.
   The gates at M0 and M8 exist to make stopping a decision rather than a drift.
5. **Report arithmetic drifts.** Attendance percentages and group roll-ups are
   easy to port *nearly* right. Port the tests first, then the code.

## The cheaper alternative, if the goal allows it

If what is actually wanted is Python *in the stack* — for reporting, analytics,
bulk imports, or an ML feature later — that is available without touching the
153 endpoints. Stand up a Python service alongside the existing API, give it
access to the same database, and route the new work to it. Postgres makes this
*more* attractive, since the Python data ecosystem treats it as the default.

Python in production in weeks instead of months, with the working ERP left
alone. It is only the wrong answer if the goal is to stop maintaining PHP
altogether — which is legitimate, and if it is the goal, the plan above is how
to get there.

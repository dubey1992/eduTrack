# Migrating to Python and PostgreSQL

**Status: M8 passed — the gate is met.** Decided to proceed on 2026-09-16.

| Phase | |
|---|---|
| M0 Decisions | Partly answered — see below |
| M1 PostgreSQL locally, schema parity | **Done** 2026-09-16 |
| M2 Portability fixes | **Done** 2026-09-16 |
| M3 Data migration rehearsal | **Done** 2026-09-16 |
| M4 Both databases in CI | **Done** — green in CI |
| M5 Staging | **Deleted** — nothing is deployed |
| M6 Contract suite | **Done** — 153/153 endpoints |
| M7 Skeleton | **Done** — 33 models, round-tripped |
| M8 Auth, tenancy, Students — **GATE** | **Passed** 2026-09-16 |
| M9 Wave 1 — foundations | **Done** — 52 of 52 |
| M10 Wave 2 — people and daily operations | **Done** — 20 of 20, plus the notification core |
| M11 Wave 3 — derived and outbound | **Done** 2026-09-17 — contract suite green on both, Flutter suite and integration test pass against Django |
| M12 onwards | Not started |

**Answered at M0:** Django + DRF is the framework, and **hosting is cPanel**
(decided 2026-09-16). AWS is a later plan, not a parallel one — so nothing
here is built twice, and the constraints below are real constraints rather
than a hedge.

What cPanel settles:

| | |
|---|---|
| Background work | **cron**, not a broker. No Celery, no Redis — CLAUDE.md §6 stands |
| The Python process | Passenger, one persistent process |
| M12 | the **first deployment**, not a cutover — nothing is live to switch from |

**What that unblocks, and what it now requires.** Three things were waiting on
this answer, and all three are now specified rather than open:

- **A queue.** Laravel runs `QUEUE_CONNECTION=database` with a cron calling
  `queue:work --stop-when-empty`. Django ships no equivalent, so the Python
  side needs a jobs table, a worker management command, and a cron entry —
  the same shape, deliberately, because it is the shape the host allows.
- **A PDF renderer.** The payment receipt is a Blade view through
  `barryvdh/laravel-dompdf`. The Python analogue has to be pure Python:
  shared hosting has no cairo or pango, which rules out WeasyPrint.
  `xhtml2pdf` takes the same HTML-and-CSS input dompdf does.
- **Mail.** `MAIL_MAILER=log` in development today, so nothing is actually
  delivered; the Python side needs to reach the same SMTP settings, not
  invent a provider.

These are shared infrastructure rather than one module's problem — payments,
communication, announcements and bulk imports all queue work — so they are
built once, as their own piece, rather than inside whichever module reaches
them first.

When AWS is planned later, the queue is the piece worth revisiting: real
workers would replace the cron, and that is a simplification to make *once*,
deliberately. Nothing else on this list changes shape.

Replacing the Laravel/PHP backend with Python, and MySQL with PostgreSQL.

**No school is using this yet.** Corrected on 2026-09-16: nobody goes live until
every module is finished, which removes most of what made the back half of this
plan dangerous. Earlier revisions were written around a live pilot school and
were wrong about it. Hosting happens only once every phase is complete
(confirmed 2026-09-16), which is what deleted M5 outright.

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

So the phases below run in three tracks, in order: **get to Postgres** (M0–M4),
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
4. **No phase touches production** except M12, which is the first deployment
   there has ever been. Nothing is live until every phase is done.
5. **Real data is never the test subject.** Migrations are rehearsed on a
   copy, every time. There is no live school's data to lose today, and this
   rule is what keeps that true on the day there is.

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
what keeps M1–M4 reversible: at no point is there a commit that only works on
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

**Fixed 2026-09-16.** No helper was needed: Laravel's own
`whereLike($column, $value, caseSensitive: false)` compiles to `ilike` on
PostgreSQL and `like` on MySQL. All 14 sites use it, and
`SearchCaseInsensitivityTest` searches in deliberately the wrong case across
students, staff, announcements and early-access requests.

Worth recording how that test behaved before the fix, because it is the
clearest demonstration of what "silent" means here: **6 of 6 passed on MySQL
and 5 of 6 failed on PostgreSQL.** Writing it first also caught a test passing
for the wrong reason — announcements name their filter `q`, not `search`, so
the parameter was ignored and an unfiltered list was satisfying the
assertion.

### Email uniqueness stops being case-insensitive — `users.email`

Today `Head@school.com` and `head@school.com` cannot both exist. Under Postgres
they can — two accounts for one person, one of them unreachable by whoever
types the other spelling. This is an authentication boundary quietly changing
meaning, so it is the one to get right first.

**Fixed 2026-09-16**, and the failures first proved how bad it would have been:
on PostgreSQL the duplicate account was **created** (201 where 422 belongs), and
signing in with a capitalised address returned **401**.

Normalised to lowercase on write, on the `User` model rather than in the
services so that imports, factories and seeders cannot route around it, plus a
`LowercasesEmail` trait on the six requests that take an address, so validation
asks about the same form that gets stored. A migration lowercases existing rows.

No `lower(email)` index proved necessary: with every row stored lowercase the
existing unique index enforces it on either database, which is simpler and
cannot be raced by two requests arriving together.

**That migration is safe in this direction only.** Lowercasing on MySQL cannot
collide, because its collation already forbids two addresses differing only by
case. Importing first and normalising afterwards is what would fail — by then
they are two real rows, and one of them has to be somebody's problem.

### Timestamps and per-school timezones — 17 timestamp, 14 date columns

eduTrack pins `APP_TIMEZONE` to UTC and resolves each school's local day in
application code (`docs/timezones.md`). Choose `timestamptz` carelessly and
Postgres shifts values by the session timezone on read, moving attendance
across a day boundary for any school far enough east or west.

**Decided 2026-09-16: `timestamp without time zone` everywhere**, which is what
Laravel's `timestamp()` already produces — all 84 columns came out that way with
no migration edited. The connection is pinned to UTC in `config/database.php`
and the local server in `postgresql.conf`.

The decision was never much in doubt; the risk is that somebody later changes
it, because switching a column to `timestamptz` reads like an improvement right
up until the day it isn't. `PostgresTemporalStorageTest` fails if any column
grows a timezone of its own, if the connection is not UTC, or if an instant does
not come back exactly as written. The twenty tests in `SchoolTimezoneTest` would
catch the damage; these catch the cause.

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

### What happened — 2026-09-16

**Done. Three clean runs**, each from an empty database, each ending in the
verification passing with no manual step: 34 tables, 165 rows, 33 sequences.

**pgloader turned out to be the wrong tool, and not narrowly.** It is a Linux
and macOS program: it does not run on Windows, where this is developed, and it
is not installable on the shared cPanel host where the real cutover has to
happen. A tool that cannot run in the place it is needed is not a plan. The
import is `php artisan db:copy` instead — version-controlled, reviewable,
tested, and able to run anywhere PHP does, which is the one thing production is
guaranteed to have. The schema is not its problem; `migrate` builds that, and
M1 proved the result identical.

It has to get three things right, and each is a way a migration fails quietly:

- **Order.** Rows arrive so that foreign keys always have something to point
  at, worked out from the target's own constraints rather than a hardcoded
  list that goes stale the first time somebody adds a table.
- **Booleans.** MySQL hands back `0` and `1` where PostgreSQL wants
  `true`/`false` and will not take the integers.
- **Sequences.** `setval` on all 33, then **asserted** — the verification fails
  if any sequence sits below its table's highest id.

**Proved rather than assumed.** After an import the highest school id was 114;
an insert then received 115, not a collision. That is the actual claim, and it
is the one the row counts cannot make.

Two bugs the rehearsal found, which is what rehearsals are for:

- `pg_get_serial_sequence` **raises** rather than returning null for a table
  with no `id` column, so `password_reset_tokens` — keyed on the address —
  aborted the run after every row had already copied.
- `getTableListing()` on MySQL returns tables from **every schema the account
  can see**. On a machine with a test database beside the real one that is the
  same table twice, and no ordering can resolve it: the command aborted with a
  bogus "circular foreign keys" error. The listing is scoped to one schema now.

`CopyDatabaseCommandTest` pins the ordering, the exclusions and the
token-carrying decision, so none of it depends on somebody remembering to
rehearse again.

**One deliberate inclusion.** `personal_access_tokens` is copied. This phase
moves database but keeps the application, so Sanctum's tokens stay valid and
nobody is signed out — unlike M12, where the Python backend cannot read them
and everybody signs in again.

## M4 · Both databases in CI

**Work:** the test suite runs against MySQL *and* Postgres on every commit.

**Done when:** the whole suite is green on both. This is the phase that makes
the rest of the project safe, because from here on any behavioural difference
between the two databases fails a test rather than reaching a school.

### Half done — 2026-09-16

**The mechanism exists.** `composer test:both` runs the suite against MySQL and
then PostgreSQL in one command, using `phpunit.pgsql.xml` from M1. Verified:
**868 passed plus 3 skipped on MySQL, 871 on PostgreSQL.** The three skips are
the PostgreSQL storage guards, which have nothing to describe on MySQL.

**"On every commit" is not done, and cannot be finished here.** This repository
has no CI at all — no workflows, no pipeline. Adding one is a new capability for
the project rather than a step in this migration: it runs on somebody's
account, it needs MySQL and PostgreSQL service containers, and it will take a
few passes to go green. That is a decision to be taken deliberately, not
slipped in under a database migration.

Until it is taken, `composer test:both` before pushing is the whole of the
guarantee, and it depends on somebody remembering — which is exactly the
property CI exists to remove. Worth closing before the Python track starts,
because from M7 onwards two backends have to stay in step and nobody can hold
that in their head.

## M5 · Production on PostgreSQL — **deleted**

**This phase no longer exists. Confirmed 2026-09-16: nothing has ever been
deployed, and hosting happens only once every phase is complete.**

It was written as the risky one - take a working school offline, move its
records, and hope. There is no working school, no staging to run alongside a
live system, and no records in production to move. A phase that cannot be
started is worse than no phase: it sits in the plan looking like work
somebody has forgotten.

**What replaces it is a line in `docs/deployment.md`, not a window:** the
first deployment creates a PostgreSQL database instead of a MySQL one, points
`.env` at it, and runs the migrations. `db:copy` is not needed, because there
is nothing to copy.

This also settles what M12 is. With nothing to cut over *from*, **M12 is the
first deployment** rather than a switch between two running systems - so its
rollback, its maintenance window and its "tell the school" step all fall away
with it.

**What stops being true**, and is worth naming because earlier revisions of
this document leaned on all of it:

- No cutover window, no evenings or weekends, nobody to tell.
- No downtime that costs anything.
- **Nobody is signed out at M12.** That was the sharpest edge in the whole plan
  - the Python backend cannot read Sanctum's tokens - and it does not cut
  anybody if there is nobody signed in.
- The rollback stops being a race. Its cost was losing records created after
  the switch, and there are none.

**What was still worth building.** `db:copy` and `schema:diff` were written for
a migration that may now never need them, and they are still the right thing to
have: they are how the first real deployment gets verified, they are how any
future move between databases is done, and `schema:diff` is what proved M1's
claim in the first place. Three rehearsals against real data also found two bugs
that would otherwise have been found by a school.

### The runbook, if there is ever data to move

Kept for the third case above, and for any later migration.

#### Before the window — checks, not steps

1. **`pdo_pgsql` on the host's PHP.** "The plan offers PostgreSQL" and "PHP on
   this account can talk to it" are two different facts, and only the second
   one matters here. `php -m | grep pdo_pgsql` over SSH. If it is missing, ask
   the host to enable it; nothing below works without it.
2. **A PostgreSQL database and user exist**, created through cPanel, with the
   account prefix.
3. **The deployed commit is current.** The runbook needs `db:copy` and
   `schema:diff`.
4. **A rehearsal on a copy of production.** The number that matters is the row
   count, and finding out it is wrong should happen here rather than in the
   window.

#### The window

```bash
# 1. Stop the world.
php artisan down

# 2. Deploy the current commit, if it is not already deployed.
git pull && composer install --no-dev --optimize-autoloader

# 3. Point PG_* at the new database in .env, leaving DB_* alone.

# 4. Build the schema on PostgreSQL.
php artisan migrate --database=pgsql --force

# 5. Prove it is the same schema before putting anything in it.
php artisan schema:diff --from=mysql --to=pgsql

# 6. Copy the data. Resets every sequence and verifies row counts itself.
php artisan db:copy --from=mysql --to=pgsql

# 7. Set DB_CONNECTION=pgsql in .env, then:
php artisan config:clear

# 8. Look at it as a person: sign in, open a list, add something and delete it
#    again. That last step is what really tests the sequence reset.
php artisan up
```

#### Rollback

Set `DB_CONNECTION=mysql`, `php artisan config:clear`, done. MySQL is untouched
and current as of step 6.

That is only clean while nobody has used the system: every record created after
step 8 exists on PostgreSQL alone. Keep the MySQL database for a fortnight
either way - it costs nothing and it is the only copy of the pre-migration
state.

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

### Done — 2026-09-16

**153 of 153 endpoints, 127 tests, green against the running backend.** In
`contract/`, standard library only, no import from `backend/` anywhere in it.

Coverage is counted rather than claimed: the client records every request and
matches it against a manifest of all 153, which `RouteManifestTest` keeps
honest from the backend side - a route added without being listed fails the
build, and so does a listed route that no longer exists.

**What it found while being written**, which is the argument for having done it
before the rewrite rather than during:

- `POST /academic-years` answered `"is_current": null` for a column that is NOT
  NULL with a default of false. The Flutter client reads it as a plain bool and
  would have thrown; it escaped only because that client always sends the field
  and the suite does not. Fixed, with a backend test pinning it.
- A School Admin's leave request is approved as they raise it - there is nobody
  above the head of a school to ask. A rewrite "fixing" that to pending would
  leave an approval nobody can ever give.
- Re-deciding a decided request answers 409, not 403. The reviewer is allowed
  to review; the request has simply already been answered.
- Wrong credentials answer 401, not 422.
- List endpoints deliberately omit the nested collections their detail
  endpoints carry, which needed two shapes rather than one loose one.

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

### The gate was met — 2026-09-16

All three conditions, checked rather than asserted:

- **The Flutter app, unmodified.** The only difference from the build served on
  `:5000` is `--dart-define=API_BASE_URL`. It signs in, lists the roll,
  searches it, and deactivates and reinstates a student, all against Django.
  Not one line of Dart was touched.
- **The contract tests pass** for these endpoints: 19 of the 21 in
  `test_contract.py`'s auth, envelope, student and isolation classes. The other
  two ask `/schools` and `/payments` for a 403; Django answers 404 because
  those are M9 endpoints it does not serve yet.
- **167 Django tests**, of which 48 are ALLOW/DENY pairs over `SchoolScope` and
  `StudentPolicy`. Verified by sabotage: making every admin unrestricted for
  one run turned 22 of them red.
- **Both backends answer identically.** `GET /students` against the same rows
  returns field-for-field identical JSON from Laravel and from Django — 16
  fields per student, byte for byte. This is what found the timestamp bug
  below, and it is now the check worth repeating for every module in M9–M11.

**It was not miserable**, which is the answer the gate exists to produce.

### The bug the gate caught, and why nothing else could have

Django and Laravel were asked for the same student and their answers were
compared field by field. Fifteen of sixteen fields matched. `created_at` was
five and a half hours early.

Laravel's timestamp columns are `timestamp without time zone` holding UTC
instants — a naive column is a fine place for a UTC instant as long as
everybody agrees that is what it means. Django does not agree by default: it
expects `timestamptz`, so psycopg hands back a **naive** datetime, and
`.astimezone()` on a naive value assumes the *machine's* local zone. On a
laptop in Asia/Kolkata, every instant the API returned was shifted by the
local offset.

**All 156 Django tests passed the whole time, and always would have.** The
test database is built from the models, where Django creates the column as
`timestamp with time zone` — so in a test the value comes back already aware
and the bug cannot occur. It only exists against a schema Laravel built.

The same flaw had a second, worse instance: `has_expired()` compared a naive
`expires_at` to an aware `now()`, which raises `TypeError`. It would have
crashed on the first token anybody set an expiry on, and no test would have
shown it.

Fixed once, at the field: `school/fields.py` attaches UTC on read, and all 82
timestamp columns go through it. The regression tests in
`school/tests/test_instants.py` deliberately do not touch the database for the
thing they assert — they hand the conversion a naive datetime directly, which
is the case the test database will never produce.

Two lessons, both already in the plan and now paid for:

- **A test database built from the models proves the models agree with
  themselves, not that they agree with Laravel.** That was written in M7's
  README as a caution. This is what it looks like when it bites.
- **Comparing the two backends' actual answers is worth more than either
  one's test suite.** Both `/students` endpoints now return field-for-field
  identical JSON against the same rows, which is a stronger statement than
  any number of green tests.

### Findings that changed the plan rather than the code

1. **Nobody has to be signed out at cutover.** See M12 — Sanctum's tokens turn
   out to be portable, and this was checked against a live server in both
   directions rather than reasoned about.
2. **The contract suite can now test one backend while building its world
   through another** (`CONTRACT_SETUP_BASE_URL`). Without that it could not run
   against Python until the very last module, because it creates the school it
   works in through the API. This is what lets M9–M11 be verified as they land
   instead of all at once at the end.

What is *not* done, and is honest about it: the Add Student dialog cannot be
completed through the UI, because its class picker calls `/classes` — an M9
endpoint. The `POST /students` endpoint itself works and is covered both by
Django tests and by the contract suite; only the form that feeds it is waiting
on the next phase.

## M9 · Wave 1 — foundations

Schools, school groups, payments, users and admin accounts, academic years,
departments, subjects, classes and sections, holidays, periods.

Ported in dependency order, because everything downstream references them.

**Done when:** each module's contract tests pass and its ALLOW/DENY tests exist.

### Progress

| Module | Endpoints | |
|---|---|---|
| Schools | 6 | **Done** — identical to Laravel, envelope included |
| Timezones | 1 | **Done** |
| Users and admin accounts | 6 | **Done** |
| Academic years | 6 | **Done** |
| Departments, subjects | 10 | **Done** |
| Classes, sections, periods, holidays | 17 | **Done** |
| Payments | 7 | **Done** — with the queue and the PDF renderer it needed |

Each module is checked the way M8's bug was found: ask both backends the same
question and diff the answers, with the host and the wall clock normalised
away and nothing else. It found three things in this wave that no test on either side would
have - and one of them would have crashed the Flutter client.

**`meta.links` was missing from the Python pagination envelope.** Laravel's
`LengthAwarePaginator` emits page-link descriptors inside `meta`, including
the `...` elision for long lists. Nothing in the Flutter client reads them,
which is exactly why it went unnoticed; the module claimed to reproduce the
envelope and did not. Now ported from `UrlWindow` arm for arm.

**A list came back in the wrong envelope.** `/periods` is not paginated - a
school has eight or nine - and Laravel calls `JsonResource::withoutWrapping()`,
so a non-paginated collection is a bare array. Django wrapped it in
`{"data": [...]}`, which the Flutter client would have thrown on:
`period_api.dart` does `response.data as List`. Every Django test passed,
because the tests had been written against the wrapper.

The rule, now written down where the next module will need it: **flat for a
single resource and for a non-paginated collection; `{data, links, meta}` only
from the paginator.**

**The timezone list was wrong, and it was a calendar bug.** Django offered 598
zones where Laravel offers 419: Python's `zoneinfo` includes the
backward-compatibility aliases (`Asia/Calcutta`, `America/Buenos_Aires`,
`US/Eastern`) and PHP's list does not. A school set to `Asia/Calcutta` through
Django would be read by Laravel's `SchoolClock`, fail its check against PHP's
list, and **fall back to UTC** — moving every attendance date for that school
by five and a half hours. The canonical list is now generated from PHP and
committed as `backend-python/school/zones.py`.

### The infrastructure payments needed, built once

Payments was the last module in this wave because two of its seven endpoints
needed things no module should build for itself. Both now exist, and both are
shared: communication, announcements and bulk imports will all queue work.

**A queue.** A `queued_jobs` table, a worker management command, and a cron
entry - the same shape Laravel runs (`QUEUE_CONNECTION=database` plus
`queue:work --stop-when-empty`), because that is the shape cPanel allows.

It is a *second* table rather than Laravel's own `jobs`, and that is the
interesting decision. Laravel's payload is a serialized PHP object: the
payload *is* the class, and nothing but PHP can unserialize it. Two producers
writing two formats into one table is how a queue starts silently dropping
work. So `queued_jobs` holds a job *name* and a JSON payload, readable by
anything.

Created by a Laravel migration even though only Python uses it, because
Laravel's migrations own this schema until the cutover. Letting Django create
one table would put a table in PostgreSQL that MySQL does not have, and
`schema:diff` - the check that proved the two databases identical at M1 -
would be right to complain. It now compares 41 tables and 409 columns with no
differences.

Two rules make it safe to run from cron, where two invocations overlap if one
run takes longer than the gap between them. **Reserving is a single
conditional UPDATE**, so two workers racing for a row means one wins and the
other moves on rather than both sending the same receipt. And **a job that
throws is retried with a growing backoff**, then left reserved with its error
on the row - visible in the table rather than only in a log, and no longer
costing a worker on every pass.

**A PDF renderer.** `xhtml2pdf`, pure Python: shared hosting has no cairo or
pango, which rules out WeasyPrint. Like dompdf on the Laravel side it
understands only simple CSS, so the receipt template came across unchanged and
the document a school files looks the same after the cutover as before it.

### The ordering bug this wave found in Laravel

Comparing the two backends showed them disagreeing about the order of two
students who shared a first name. Neither was wrong about the other — both
were wrong in the same way.

Fifteen paginated lists order by a column that is not unique and offer no
tiebreaker, so the database returns ties in whatever order it likes. A page
boundary falling inside a group of equal values then **shows one record twice
and never shows another**. Reproduced on both engines, with the fix removed:

| | |
|---|---|
| MySQL | `/api/v1/users` returned 6 distinct records out of 7 — id 8 twice |
| PostgreSQL | `/api/v1/students` returned 5 out of 6 — id 1 twice |

This is live behaviour in the PHP backend today, not something the migration
introduced. Fixed on **both** backends in the same commit for the three
modules ported so far — students, schools and users — because fixing one
backend alone would have been exactly the kind of behaviour difference this
migration exists not to introduce.

`StableOrderingTest` covers each and fails without the fix on either
database. **The remaining lists have the same latent bug** and are fixed as
their modules are ported, so that every change to the live backend arrives
with a cross-backend check of the same endpoint rather than on its own.

It has appeared in every module ported since, which is the point worth
recording: this is not three unlucky lists, it is how all of them were
written.

| List | What ties |
|---|---|
| Students, users | People share first names |
| Schools | Branches of a group share a name |
| Academic years | Every school in a group starts on the same April day |
| Departments, subjects | A name is unique *within* a school, not across them |
| Staff | An employee id is unique within a school; EMP-001 exists at every one |
| Holidays | Every school in a country closes on the same national holiday |

Each was fixed on both backends when its module landed, with a case added to
`StableOrderingTest`. The remaining lists are fixed the same way as the port
reaches them.

## M10 · Wave 2 — people and daily operations

Teachers and staff, student attendance, staff attendance, leave management,
timetable.

The highest-traffic part of the product and the part a school notices within
minutes if it is wrong.

### Progress

| Module | Endpoints | |
|---|---|---|
| Teachers and staff | 4 | **Done** |
| Student attendance | 4 | **Done** |
| Staff attendance | 4 | **Done** |
| Leave management | 5 | **Done** |
| Timetable | 3 | **Done** |

Teachers and staff came first because everything else in this wave hangs off
an employment record: attendance is marked against one, leave is taken by one,
and a timetable entry names one as the teacher.

### The plan had communication in the wrong phase

M11 lists communication. But **marking a register alerts a guardian**,
approving leave alerts the person who asked for it, and a bus trip alerts
both - so three of M10's five modules depend on it. Porting attendance first
would have given a school a backend that looks finished and silently stops
sending absence alerts, which is the same failure that kept payments waiting
for its queue.

So the notification *core* moved forward and landed before attendance:
template rendering, the school's alert switches, the message log, the SMS
gateway abstraction (CLAUDE.md rule 14) and the send job. The communication
**endpoints** stay in M11 - only the part other modules call came early.

The rule it exists to protect, and the one most easily lost in a port: **a
switched-off alert is not logged at all.** It is not "skipped" - the school
never wanted the message, and one row per student per day would bury the log
that exists to be read. Only a message the school *did* want but that could
not be delivered earns a row.

### A second column-type trap, found the same way as the first

`manage.py check_models` refused the new `queued_jobs` table:

    QueuedJob   the JSON object must be str, bytes or bytearray, not dict

Laravel's `$table->json()` creates a **`json`** column on PostgreSQL. Django's
JSONField assumes **`jsonb`**: with psycopg3 it registers a loader so `jsonb`
arrives as a raw string it decodes itself, and that registration does not
cover `json`. A `json` column therefore arrives already decoded, and Django
hands a dict to `json.loads`.

**All 461 tests passed**, because the test database is built from the models
and Django creates `jsonb` there. Exactly the blind spot the timestamp bug
had at M8, in a different column type.

Fixed at the field, like the timestamps. Changing the column to `jsonb` would
also have worked and was rejected: it is the better column type, but it would
make PostgreSQL and MySQL disagree, and `schema:diff` proving those two
identical is load-bearing for the whole migration.

The pattern is now named where it will be needed again: **any time Django's
default column type differs from Laravel's, the test suite is blind to it and
`check_models` is not.**

It is also the module where the two-rows-or-neither rule lives. The Add
Employee screen is one form and creates a login *and* an employment profile in
one transaction, because half an employee is not a state the product has a
screen for - a login with no profile is invisible to Attendance and Leave, and
a profile with no login is somebody on a roster who cannot sign in.

### Leave is the module that writes into another module

Approving leave marks every working day in its range as `leave` on the staff
attendance register. That is the point of it: an approved request and the
register can never quietly disagree about whether somebody was expected in.

Two details of that sync are easy to drop in a port and both were kept.
Weekends and holidays inside the range get **no** mark, because they are not
attendance days and the calendar already refuses attendance on them - marking
them would put a row where the rest of the product says there can be none. And
a **School Admin's own request approves itself** on application, with a remark
saying why: nobody else has standing to review the head of a school. A Sub
Admin is still subordinate to the admin who created them and waits like
everyone else.

The other rule worth naming: **nobody reviews their own leave.** An HOD heads
the department they belong to, so without an explicit check they would pass
the department test for their own request.

### The refusals are where a port drifts

A happy path gets copied carefully. An error path gets copied from memory - so
leave and timetable were diffed on their refusals as well as their answers,
with a second comparer alongside `compare.py` that sends the same *rejected*
request to both backends. Every one of those writes nothing, so it is safe to
send twice: an unknown leave type, a reason past the column, an end date
before the start, a range that is all weekend, days already spoken for, a
decision taken twice, a teacher reviewing themselves, a leave that is not
there. Eleven cases for leave and seven for the timetable, identical in status
and body.

That is how the timetable's 404 was caught. A grid asked for with somebody
else's `class_section_id` answers **404, not 403** - the id came from a query
string, and a stranger should not learn that it is real. Both backends
answered 404 and the bodies differed:

    - "code": "NOT_FOUND",      "message": "The requested resource was not found."
    + "code": "HTTP_ERROR",     "message": "Not found."

The handler mapped Django's `Http404`, which `get_object_or_404` raises, and
not DRF's own `NotFound`, which a view raises directly. Both are the same
answer to a client and now read the same. No test on either side could have
seen it: each backend was internally consistent, and the contract suite only
asserts the status.

The timetable's own rule is the one its unique key cannot enforce: that key
guards a single class section's grid, so **a teacher standing in two rooms at
once** is a collision between two of them and only the service can see it.

## M11 · Wave 3 — derived and outbound

Daily teaching reports, syllabus tracking, HOD monitoring, transport (master
data and trips), communication, announcements, early access, dashboards and the
four reports.

### Progress

Sliced in dependency order, so each slice only builds on what already exists.

| # | Slice | Endpoints | |
|---|---|---|---|
| 1 | Daily teaching reports | 4 | **Done** |
| 2 | Syllabus topics and progress | 6 | **Done** |
| 3 | HOD department report | 1 | **Done** |
| 4 | Communication and the in-app inbox | 13 | **Done** |
| 5 | Announcements | 5 | **Done** |
| 6 | Transport master data and student assignment | 21 | **Done** |
| 7 | Transport trips | 7 | **Done** |
| 8 | Early access, forgot and reset password | 6 | **Done** |
| 9 | Dashboard, the four reports, and the staff and subject importers | 5 + importers | **Done** |

Forgot and reset password were never in this phase's list and are not served
by Python yet either, so they ride with early access - both send mail.

### Teaching reports

A report belongs to a period the teacher actually taught: their own
timetable entry (a 403 otherwise, because that is ownership), on that period's
weekday, not in the future on the *school's* calendar, and not on a holiday or
a weekend. Nobody reviews their own report - the same HOD trap as leave.

Laravel lists every failing rule on a field, so a future date on the wrong
weekday gets two messages, and a bad date is still reported when the topic is
missing too. DRF skips `validate()` as soon as any field fails, which would
have hidden the date; both rules run in the field's own validator instead.

The list ordered by date and then teacher, and a teacher files one report per
period - so on any busy day those tie on every row. `StableOrderingTest`
gained a case; without the tiebreaker PostgreSQL paged `1,1,3,4,5,6`.

Compared live as root, a school admin, a teacher and another school: 25 reads
and refusals identical, and the file-then-review path identical with only the
id, date and timestamp masked.

Reports last, on purpose: they read from everything above, so they are the
broadest end-to-end proof that the port is faithful. The per-branch group
reporting rules in `docs/reports.md` and `docs/branches.md` are the subtlest
arithmetic in the system — combined rates are recomputed from raw counts, never
averaged — and must be ported with their tests, not re-derived.

**Done when:** 153 of 153 endpoints answer identically, and the Flutter suite of
705 tests passes against the Python backend.

### Syllabus, and a leak found before porting it

Reading Laravel's syllabus code to port it turned up two reads that never
checked the school. Both take a `subject_id` in the query string, and `exists`
only proves a subject is real:

- the **outline list** returned any school's topics to anyone who changed the
  id;
- the **checklist** checked the *section* against the actor's school but not
  the subject, so another school's subject paired with one of the actor's own
  sections handed over that school's topic list.

Both were confirmed against the running Laravel API before anything changed,
then fixed on both backends together rather than ported: a subject outside the
actor's schools is a **404**, the same answer the timetable grid gives for an
id from a query string. Each fix has an ALLOW and a DENY test on both sides,
and the DENY tests were run without the fix to prove they fail - 200 on
Laravel, a failure on Django.

This is a behaviour change to the live contract, and a deliberate one: no
client could legitimately depend on reading another school's syllabus.

One arithmetic trap: the checklist's `progress_percent` uses PHP's `round()`,
which takes halves away from zero, and Python's rounds them to even. One topic
of eight is 12.5% - 13 in PHP, 12 from a bare `round()`. Ported with an
explicit half-up and a test that fails under `round()`.

Compared live on 29 reads and refusals, including the two DENY cases, and on
the add, edit, tick, read and remove path with ids and timestamps masked -
identical.

### The HOD report, and four things it turned up

One endpoint, and the densest arithmetic ported so far. Laravel's own August
fixture was ported number for number - 18 working days, 8.3% attendance, 2.5
leave days, 15 classes assigned and 3 taught, 33% syllabus - so a metric
computed differently fails before it reaches a diff.

**Laravel: a shorter month asked for late in a month computed the next one.**
`Carbon::createFromFormat('Y-m', ...)` takes the missing day from today, so
February asked for on March 30th parsed as March 2nd and the report showed
March's figures under February's label. Fixed with `'!Y-m'`, which
`DateFormats` already used; the test fails at 21 working days without it.

**Laravel: today never counted at a school east of UTC.**
`HolidayService::workingDates` walked from one end to the other comparing
*instants*, and callers handed it UTC midnight for one end and the school's
midnight for the other. Midnight on the 17th in Kolkata is 18:30 on the 16th
in UTC, so the 17th never passed - every school in India lost today from its
current-month attendance denominator, and the reports module lost it from any
range ending today. Found only because the Python port compares calendar dates
and the live diff said 12 against 13. Fixed at the root, so every caller is
fixed at once; the callers that already passed UTC dates are unaffected. Tests
in the HOD report and the reports suite fail without it (11 and 6).

**Python: every paginated list answered 404 for a page that does not exist.**
DRF's paginator refuses junk, zero, negative and past-the-end page numbers;
Laravel treats the first three as page 1 and answers the last with an empty
page. Wrong since M8 and never seen, because no test and no diff had asked for
a page outside the range. Fixed in `LaravelPagination`, and all 14 ported
lists compared live on five page edge cases each - 70 identical.

**The diff tool itself was blind to number types.** Python compares `50 ==
50.0` and `True == 1` as equal, so `compare.py` could not have seen PHP writing
`50` where Python writes `50.0` - which it does for every whole-number float.
The comparer is now type-strict, and every earlier slice's comparison was
re-run under it: identical. The port writes whole floats as ints (`php_number`)
and rounds to one place the way PHP 8.3 does (`php_round_1`: half away from
zero, after pre-rounding to 15 significant digits) - 6.25% is 6.3 in PHP and
6.2 from Python's `round()`, and the live data was seeded to land on exactly
that.

18 cases compared live against Laravel after the fixes, type-strict -
identical.

### Communication and the inbox

Nine endpoints for the Communication Center - the message log, its tiles, the
templates and the alert switches - and four for the inbox. The notification
core that writes messages came across before attendance; this slice is the
part people read and configure.

**The order of checks differs endpoint to endpoint, and is contract.** The log
authorizes before it validates, so a teacher with junk filters is a 403.
Rewording a template checks the event before anything else, so an event that
does not exist is a 404 even to somebody who may not configure. Saving the
switches authorizes, validates, then looks for the school. And a Super Admin
with no school reads settings for school `0` - Laravel casts the missing id to
an int - so the port does too.

**A second pre-existing difference, in a shared field.** Laravel's `boolean`
rule accepts `true`, `false`, `0`, `1`, `"0"` and `"1"` and nothing else;
DRF's BooleanField also takes `"yes"`, `"true"`, `"on"` and more. So the
syllabus tick and an academic year's `is_current` quietly accepted requests
Laravel answers with a 422, since they were ported. Fixed in
`LaravelBooleanField`, confirmed live on both backends before and after.

**Search leaves wildcards alone.** Laravel's case-insensitive `whereLike` does
not escape `%` or `_` in the term, so searching the log for `%` matches every
row; Django's `icontains` escapes them. The port uses a small `ilike` lookup
that behaves as Laravel's does.

Compared live on 50 cases - reads from four accounts, every refusal captured
from Laravel first, and writes that settle to the same state when sent twice
(the same template body twice must leave `updated_at` alone on the second) -
identical, type-strict.

### Announcements, and the third cross-school read

Publishing counts the audience in the request and fans it out on the queue, a
chunk at a time; a notice deleted before the worker reaches it is not sent.
Laravel's own fixture is ported number for number - 6 reached, 4 in-app and 7
SMS copies, 2 of them skipped for want of a number.

**Laravel: the preview named another school's classes and departments.**
`audience_id` comes straight off the query string, the policy lets any admin
through, and the label was looked up unscoped - so an admin of one school read
another school's department and class names by trying ids. Confirmed live
before the change: school 33's admin read "Contract Dept 7k72giz8" and "Grade
7k A" from school 25. The label is now looked up inside the school being
announced to; a foreign id gets the same generic "Department" or "Class" as an
id that does not exist, so trying ids tells a caller nothing. Publishing is
unaffected, because its target was already validated to the school. ALLOW and
DENY tests on both backends; each DENY test fails with the fix removed.

That is the third read found this way - syllabus, then the checklist, now this
- and all three had the same shape: an id taken from the request, checked for
existence, never for ownership.

Compared live on 36 cases and on publish, delete and read-after-delete -
identical, type-strict.

### Transport master data

Vehicles, drivers, routes and their stops, and which student rides which
route - 21 endpoints, not the 16 first counted.

Read by everyone who works with the buses at a school; changed by its admins
only. Nothing in use is deleted: a vehicle or driver on a route, a route with
riders or trips, a stop with riders are each refused with a sentence naming
what is in the way. A route keeps its own vehicle and driver even after they
are deactivated, and a vehicle's seats limit how many students its route takes
- except that moving a student already on the route between its stops always
works.

**Four more lists tied on a name.** Vehicles, drivers and routes ordered by
name alone, which is unique within one school at most - every school has a
Bus 1, so a Super Admin's list ties on every row. The riders on a route
ordered by stop and first name. `StableOrderingTest` gained two cases; without
the tiebreakers PostgreSQL paged `1,1,3,4,5,6` and `6,6,4,3,2,1`.

**The test database has no cascades.** Laravel deletes a route's stops through
the foreign key's `ON DELETE CASCADE`. The Django test database is built from
the models, whose foreign keys cascade nothing, so the port's route delete
failed in tests while it would have worked in production. The service now
deletes the stops itself, in one transaction with the route - the same effect
on the real schema, and a delete that is actually tested. The same family of
blind spot as the timestamp and JSON column types: the test database is
Django's idea of the schema, not the schema.

Compared live on 48 reads and refusals, and on a full build-and-tear-down -
vehicle, driver, route, stop, a rider moved on and back, and every delete -
identical, type-strict, with ids masked.

### Transport trips

Starting a trip, reaching its stops, boarding and dropping its riders, ending
or cancelling it. A route runs one trip per direction per day, one at a time,
on a working day at the school, with an active vehicle and driver; a rider
boards then drops, or is absent, and never goes back; a trip does not end with
anybody aboard, and ending it marks everybody who never boarded absent. Every
state change is re-checked under a row lock, because it is somebody on a bus
tapping a phone. Guardians are told, on the school's clock.

**Two more orderings made fixed, on both backends.** The trip list ordered by
date and start time, stored to the second - and a school's buses leave
together; PostgreSQL paged `1,1,3,4,5,6`. And a trip's riders ordered by stop
alone, created from an unordered query, so the riders at one stop came back in
whatever order the database chose. Riders are now created in assignment order
and read back by stop and then id.

**The test database has no SET NULL either.** Deleting a stop nulls three
references to it in the real schema - a trip's current stop, a rider's stop,
an event's stop - so that trip history keeps the stop's *name* after the stop
is gone. The test database, built from the models, has no such rule, and the
port's stop delete would have failed there. It clears the three references
itself, in one transaction, the same as the route delete's stops.

With this slice every transport endpoint is served by Python, and all 83
contract tests covering the ported modules pass against it.

Compared live by running a whole trip day through each backend on identical
routes - 21 steps from a refused start to a finished trip that refuses
everything - identical but for the two messages that name the route.

### Early access and password resets

The endpoints a stranger can reach without an account. The signup form answers
the same way whether a school is new or correcting a request still open, and
is throttled; the queue is the Super Admin's, and *converted* is set only by
onboarding a school.

**A reset link either backend sends, either backend honours.** Laravel's
broker keeps a bcrypt hash of each token in `password_reset_tokens`; the port
uses the same table and the same hashing, a one-hour expiry, one use, a
one-minute gap between links, and it signs the account out everywhere. Proved
live in both directions: a link Laravel emailed reset the password through
Django, and a link Django emailed reset it back through Laravel - each link
then refused on the other backend once spent.

**The email goes on the queue.** Laravel sends it inside the request, which
makes "this address has an account" measurably slower than "it does not" - a
way to find out which addresses exist. Queued, both return at once. The job
carries only the user's id and makes the token when it runs, so a live token
never sits in a queue row.

**Laravel: the reset refusal broke the envelope.** The controller built its
own response with `'details' => []`, which PHP writes as a JSON array - the
one error in the API whose details were not an object. The client tolerated
it; the contract says `{}`. Fixed, with a test that fails without it.

**Two importers are still Laravel's.** Bulk upload was ported for students in
M8 with the note that the rest would arrive with their modules. Staff and
subjects never did, and the contract suite's import tests say so. They join
the last slice.

### Dashboard, the four reports, and the last importers

The dashboard, the four reports (`school/reports/`, one module each, with
`ReportRange` and the group stitching beside them), and bulk upload for staff,
subjects, vehicles and drivers. With them the contract suite passes against
both backends - 127 tests, 153 of 153 endpoints - for the first time.

**Laravel: a head of department who heads nothing saw the whole school.** The
staff-attendance and teaching-coverage reports narrow an HOD with
`->when($filters['department_ids'] ?? null, ...)`, and an empty list is falsy -
so an HOD with no department was not narrowed at all and got every employee
and every subject. Confirmed against the running API before changing
anything, then fixed on both backends: an empty scope is a scope. The tests
fail without the fix on both sides.

**Python: a capital letter in an address locked the account out.** Laravel
stores every address lowercase through a mutator on `User`; the port only
lowercased in the forms that had been written by hand. The importer went
around them, so `Kavya.D@...` was stored as typed and sign-in - which does
lowercase - could never find it. Wrong for any create path that skipped a form,
since M8. Now `User.save()` lowercases like the mutator, and forgot/reset
password lowercase like `LowercasesEmail`. The two mixed-case accounts the
importer had made in the throwaway database were corrected by hand.

**Both: spreadsheets are checked case-blind, as they are read.** The importers
look departments and teachers up ignoring case - a spreadsheet cell is not a
dropdown - but validated them with `exists`, which compares with `=`. MySQL's
collation hid that; on PostgreSQL "science" was refused, and a staff address
differing from an existing one only in case passed `unique` and then hit the
unique index mid-import with a 500. `MatchesIgnoringCase` (Laravel) and
`rules.matching` (Python) compare `LOWER(column)`. Other unique codes -
employee ids, subject codes - still compare exactly on PostgreSQL where MySQL
did not; that is a wider question than the importers and is left open.

**Both: tied rows in a fixed order.** Students sharing a name, staff sharing a
name (sorted in PHP after the query, so the query needed its own order),
subjects sharing a name, and branches sharing a name now break ties by id; a
`StableOrderingTest` case per report fails on PostgreSQL without each one. Route
names are unique per school, so routes needed nothing. The dashboard's money
card lists currencies alphabetically - its test cannot fail without the
ordering, because PostgreSQL's grouping happened to sort, but it pins the
contract.

**Python: `?format=csv` was a 404 before the view ran.** DRF reads `format` as
its renderer override. `URL_FORMAT_OVERRIDE` is off; the reports own the name.

**Python: an import posted as JSON was a 415.** Laravel reads any body and says
the file is missing; the view now accepts JSON too. The last contract failure.

**Arithmetic, ported to fail loudly.** Every rate is PHP's `round($x, 1)`
(`php_round_1`) and goes out as PHP writes a float; the staff rate rounds
present-plus-half-days half *up* - 2.5 days is 3, which Python's `round()` makes
2; names sort the way PHP's `<=>` compares strings; an employee with no leave
has `"leave_by_type": []`, PHP's empty array; group totals are recomputed from
counts, never averaged. Each of these has a test that was run broken - 16
sabotages, all caught.

Compared live against Laravel on seeded data chosen to land on the edges - a
holiday declared over marked days, half days, 16.7/27.8/33.3/37.5% rates, three
currencies, an HOD, a group whose branches sit 14 hours apart so their "today"
differs - type-strict: 76 single-school cases, 24 group cases, 11 CSV downloads
byte for byte including filenames, and the four importers' templates, bad rows
and good rows (with each imported account signing in on both backends).

**Transport usage's `days_run`, decided after the port.** It was the most days
any one trip status ran on, so a route that completed a trip on Monday and was
still in progress on Tuesday read as one day run, and weekend trips counted.
Decided 2026-09-17: the distinct working days with a trip in progress or
completed. Changed on both backends with the same test, and re-diffed live -
identical. See `docs/reports.md`.

### M11's done-when, checked

The Flutter unit and widget suite passes, 705 of 705. Those tests mock the
API, so they prove the app is intact rather than that Python serves it. The
end-to-end test does: `integration_test/staff_leave_flow_test.dart`, driven in
a visible Chrome through `flutter drive -d web-server --browser-name=chrome`
with `--dart-define=API_BASE_URL` pointing at Django, passes - a teacher signs
in, applies for leave and signs out, and the HOD signs in and approves it,
every request answered by Django, with the leave mark written to staff
attendance. The same run against Laravel passes too.

It had to be repaired first, and not because of Python: it was written before
logging out gained a confirmation dialog, tapped the icon and never confirmed,
so the next sign-in could not find the form - against either backend. It now
presses "Log out" in the dialog.

Two things to know when running it: `-d chrome` hangs at "Waiting for
connection from debug service", so use `-d web-server` with chromedriver on
4444; and Django's `DJANGO_CORS_ORIGINS` has to include the `--web-port`
origin, where Laravel's development CORS allows any.

## M12 · The first deployment

**Not a cutover.** Confirmed 2026-09-16: nothing has ever been deployed, and
hosting happens only once every phase is complete. So there is no running
system to switch away from, no rollback window, no decommissioning, and
nothing to tell anybody. What is left is an ordinary first deploy - to cPanel,
with PostgreSQL and the Python backend - documented in `docs/deployment.md`.

The two paragraphs below are kept because they stop being true the moment a
school does go live, and that is exactly when somebody will want them.

**Nobody is signed out.** Corrected at M8, 2026-09-16.

Every earlier revision of this plan said the opposite: that Sanctum's
`personal_access_tokens` hashes could not be validated by any Python auth, so
every signed-in user would be logged out the moment you cut over. That was
wrong, and the reason is worth stating precisely because it was a reasonable
thing to assume.

**Sanctum does not hash a token the way it hashes a password.** A password is
bcrypt. A token is a plain SHA-256 of the random half, stored in a 64-character
column, with the client holding `{id}|{random}` — see
`vendor/laravel/sanctum/src/PersonalAccessToken.php`. SHA-256 is SHA-256 in any
language, so `backend-python/school/tokens.py` issues rows Sanctum accepts and
accepts rows Sanctum issued.

Passwords cross the same boundary, for a different reason: Python's `bcrypt`
verifies PHP's `$2y$` digests and PHP's `password_verify` accepts what Python
writes. Both directions were checked against the two running servers on the
same database, not reasoned about:

| | |
|---|---|
| A password hashed by PHP | accepted by Django |
| A password hashed by Python | accepted by Laravel |
| A token issued by Django | accepted on a Laravel route |
| A token issued by Laravel | accepted on a Django route |

What this changes: **the cutover is a document-root switch and nothing else**,
and so is the rollback. Neither signs anybody out, and neither has to be
scheduled outside school hours for that reason. It also means the two backends
can serve the same session at the same time, which is what made M8 verifiable
at all.

The tests are in `backend-python/school/tests/test_interop.py`, asserted
against fixed values the running Laravel app produced rather than against
something the Python side generated — a round trip through one library proves
only that the library agrees with itself.

**Work:** maintenance page, final data sync, document root or DNS switched,
sequences reset and asserted, smoke test as a real user.

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
   the timeline doubles. Sharper now than it looked: with no school waiting,
   the pressure to keep shipping features is lower, but so is the forcing
   function that would make anybody notice the rewrite stalling.
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

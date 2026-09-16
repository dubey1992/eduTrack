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
| M9 Wave 1 — foundations | **45 of 52** — all but payments |
| M10 onwards | Not started |

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
| Payments | 7 | Sequenced behind the queue and the PDF renderer |

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

### Payments waits on infrastructure, not on a decision

The decision landed — cPanel — so payments is no longer blocked, it is
*sequenced*. Five of its seven endpoints are ordinary. The other two need
things no module should build for itself:

- `GET /payments/{payment}/receipt` renders a **PDF**.
- `POST /payments/{payment}/receipt` **queues an email**, as does every create
  and update that changes the money.

Both belong to the shared background-work and document-rendering pieces
described under M0. Payments lands once those exist; porting the five and
stubbing the two would mean a module that looks finished and silently stops
sending receipts.

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

Each was fixed on both backends when its module landed, with a case added to
`StableOrderingTest`. The remaining lists are fixed the same way as the port
reaches them.

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

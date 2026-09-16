# The API contract

The promise the backend makes to the Flutter apps, written down as tests that
speak only HTTP.

Phase M6 of [../docs/python-migration.md](../docs/python-migration.md), and the
reason the Flutter apps will not have to change when the backend is rewritten
in Python. When every test here passes against the new backend, that backend is
finished for these endpoints. Not "the developer thinks it looks right" —
finished, by a definition written before the work started.

## What makes it a contract and not just more tests

Nothing in this directory imports anything from `backend/`. It has no database
access, no framework, no knowledge of how an answer was produced. It asks over
HTTP and reads JSON, which is exactly what the Flutter client does — and if it
could import from the backend it would stop being able to test the replacement.

The standard library only, deliberately. This has to run on a developer's
laptop, in CI, and potentially on the production host, against two different
backends, for months. A dependency it could fail to install is a dependency it
should not have.

It asserts three things:

- **Shapes.** Every field the client reads, present and of the right type.
  Extra fields are fine — adding one cannot break a client that ignores what it
  does not recognise, and forbidding them would make every additive change a
  contract failure.
- **Envelopes.** `{code, message, details}` for every error and
  `{data, meta}` for every list. The client renders `message` to the user and
  reads `details.errors` to mark up a form, so an error in the wrong shape is
  an error nobody sees properly.
- **Isolation.** One school must never read another's records. These are the
  tests that matter most, because a rewrite is exactly when that breaks.

## It needs a database you do not care about

**This suite creates schools, accounts, classes and students, and it cannot
remove them.**

That is not a gap here. The API has no delete-a-school endpoint on purpose —
erasing a school's records is not something a school management system should
offer — so deactivating is as far as any caller can go. Every run leaves data
behind permanently.

So it refuses to start unless you set `CONTRACT_DISPOSABLE_DB=yes`. "It is on
localhost" is deliberately **not** enough: the first time this suite ran it was
pointed at an ordinary local development database and left four schools, four
accounts and three students in it that no endpoint could remove.

## Running it

Stand up a second API instance on a throwaway database, so the one you
develop against is never in reach:

```bash
cd backend

# A database you are happy to lose. edutrack_testing already is one.
DB_DATABASE=edutrack_testing php artisan migrate:fresh --force

SUPER_ADMIN_EMAIL=contract.root@example.invalid \
SUPER_ADMIN_PASSWORD='choose-one' \
DB_DATABASE=edutrack_testing php artisan db:seed --class=SuperAdminSeeder --force

# Its own port, so the development server on 8000 keeps running untouched.
DB_DATABASE=edutrack_testing php artisan serve --port=8001
```

Then, from the repository root:

```bash
CONTRACT_BASE_URL=http://127.0.0.1:8001/api/v1 \
CONTRACT_DISPOSABLE_DB=yes \
CONTRACT_SUPER_ADMIN_EMAIL=contract.root@example.invalid \
CONTRACT_SUPER_ADMIN_PASSWORD='the-one-you-chose' \
python contract/run.py
```

`pytest contract/` also works if you prefer it — these are plain `unittest`
classes and pytest collects them.

One thing to avoid: do not run this and `php artisan test` against the same
database at the same time. The test suite rebuilds the schema underneath
whatever else is using it, and the failures that follow look like contract
violations rather than the collision they are.

## Environment

| Variable | Meaning |
|---|---|
| `CONTRACT_BASE_URL` | The backend under test. Default `http://127.0.0.1:8000/api/v1` |
| `CONTRACT_SETUP_BASE_URL` | The backend the world is *built* through. Defaults to the one under test |
| `CONTRACT_DISPOSABLE_DB` | Must be `yes`. There is no default, on purpose |
| `CONTRACT_SUPER_ADMIN_EMAIL` | An account that can onboard a school |
| `CONTRACT_SUPER_ADMIN_PASSWORD` | Its password |

## Testing a backend that cannot build its own world yet

Added at M8, and it is what makes this suite useful *during* the port rather
than only at the end of it.

The suite creates the school it works in through the API — two schools, their
accounts, a class, a section, a student. The Python backend grows one module at
a time, so for most of the migration it can serve the endpoints under test
while being quite unable to create the school they are about. Without a way to
split those, none of these tests could run against Python until the very last
module landed, which is the worst possible moment to find out.

So setup and assertion can point at different instances:

```bash
CONTRACT_BASE_URL=http://127.0.0.1:8002/api/v1        \
CONTRACT_SETUP_BASE_URL=http://127.0.0.1:8001/api/v1  \
CONTRACT_DISPOSABLE_DB=yes                            \
CONTRACT_SUPER_ADMIN_EMAIL=contract.root@example.invalid \
CONTRACT_SUPER_ADMIN_PASSWORD='the-one-you-chose'     \
python -m unittest test_contract.Authentication test_contract.Students \
                   test_contract.Envelopes test_contract.SchoolIsolation
```

Laravel on 8001 builds the school; Django on 8002 is the one being judged.
**Both must be on the same database**, which is the whole reason the PostgreSQL
move came first and the two backends stay runnable side by side.

Two things stay honest under the split. Each client signs in on the backend it
will be used against — so a run pointed at Django proves Django can issue a
token for a password Laravel hashed. And coverage is only recorded for the
backend under test, so building a world elsewhere cannot flatter the figure.

## The files

| | |
|---|---|
| `client.py` | HTTP and nothing else. Returns 4xx as answers, since most of this suite is about what the errors look like |
| `shapes.py` | The promised shapes, and the assertions that check them |
| `world.py` | Builds two unrelated schools through the API, so isolation can be asserted rather than hoped |
| `test_contract.py` | The contract itself |
| `run.py` | Entry point |

## Coverage

**153 of 153 endpoints, 127 tests.** The figure is counted, not claimed: every
request the client makes is recorded and matched against `endpoints.py`, so the
number cannot drift from what the suite actually does. `python contract/run.py`
prints it, along with anything still missing and anything called that the
manifest does not declare.

## Rebuild the database periodically, and not only for tidiness

Every run leaves records behind, so the throwaway database grows — it reached
40 schools, 103 users and 56 students before being rebuilt on 2026-09-16.

That is worth doing for a reason beyond housekeeping. **Accumulated litter can
make the coverage figure lie.** `test_a_super_admin_reads_and_reviews_the_queue`
skipped itself when the early-access queue was empty, and it never was: earlier
runs had always left an application behind. On the rebuilt database it skipped,
and coverage fell to 151/153 — two endpoints that had read as covered for weeks
were only ever reached by leftovers. Worse, tests run in alphabetical order,
which puts that test *before* the one that applies, so on any genuinely fresh
database it could never have worked.

The test now creates what it needs, which is the same lesson as `world.shared()`:
depend on nothing that a previous run happened to leave lying around.

To rebuild, from `backend/`:

```bash
set -a; . ./.env.contract; set +a          # DB_CONNECTION=pgsql lives here
php artisan migrate:fresh --database=pgsql --force
php artisan db:seed --class=SuperAdminSeeder --database=pgsql --force
```

**Check what that is pointing at before running it.** The default connection in
this project is MySQL, which is the development database with real data in it;
`--database=pgsql` and the `DB_CONNECTION` in `.env.contract` both have to say
PostgreSQL. `backend/.env.contract` is gitignored and holds the contract
instance's settings — it exists because the Super Admin password used to live
only in whichever shell had seeded the database, and when that shell closed the
only way back in was to reset the account.

## One thing it found already

The suite was written expecting a wrong password to answer `422`. It answers
`401 UNAUTHENTICATED`, and it is right to: the form was fine, the answer was
no. The test was corrected to match the API rather than the other way round —
which is what a contract suite is for. It records what the backend actually
promises, not what somebody assumed it promised.

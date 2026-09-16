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
| `CONTRACT_BASE_URL` | Where the API is. Default `http://127.0.0.1:8000/api/v1` |
| `CONTRACT_DISPOSABLE_DB` | Must be `yes`. There is no default, on purpose |
| `CONTRACT_SUPER_ADMIN_EMAIL` | An account that can onboard a school |
| `CONTRACT_SUPER_ADMIN_PASSWORD` | Its password |

## The files

| | |
|---|---|
| `client.py` | HTTP and nothing else. Returns 4xx as answers, since most of this suite is about what the errors look like |
| `shapes.py` | The promised shapes, and the assertions that check them |
| `world.py` | Builds two unrelated schools through the API, so isolation can be asserted rather than hoped |
| `test_contract.py` | The contract itself |
| `run.py` | Entry point |

## What is covered so far

Auth, the two envelopes, students end to end, school isolation, and the Super
Admin's view of schools — 23 tests.

**That is not all 153 endpoints.** It is the harness plus the highest-risk
slice: the shapes every other endpoint reuses, and the isolation rules that a
rewrite is most likely to break. Adding an endpoint is now mechanical — a shape
in `shapes.py` and a handful of assertions — and the plan's bar for M6 is all
153, endpoint by endpoint, before the Python work starts in earnest.

## One thing it found already

The suite was written expecting a wrong password to answer `422`. It answers
`401 UNAUTHENTICATED`, and it is right to: the form was fine, the answer was
no. The test was corrected to match the API rather than the other way round —
which is what a contract suite is for. It records what the backend actually
promises, not what somebody assumed it promised.

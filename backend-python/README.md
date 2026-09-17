# The Python backend

Phase M7 onward of [../docs/python-migration.md](../docs/python-migration.md).
Django + DRF, replacing `backend/` — eventually. Until then both run, and
nothing here assumes it owns the database or the port.

## What exists so far

**M8 and M9: auth, tenancy, and all of Wave 1** — 52 endpoints. The rest
arrive module by module from M10, each landing only when its contract tests
pass ([../contract/README.md](../contract/README.md)). Anything not listed
below answers a `NOT_FOUND` envelope, not an HTML page.

| Endpoint | |
|---|---|
| `POST /auth/login`, `/auth/logout`, `/auth/change-password` | Sanctum-compatible tokens |
| `GET /me` | the session user, including `manages_branches` |
| `GET`/`POST /students`, `GET`/`PATCH /students/{id}` | list, admit, read, edit |
| `PATCH /students/{id}/activate`, `/deactivate` | a student is never deleted |
| `GET /imports/students/template`, `POST /imports/students` | bulk upload, all or nothing |
| `GET`/`POST /schools`, `GET`/`PATCH /schools/{id}` | platform records; a group is one level deep |
| `PATCH /schools/{id}/activate`, `/deactivate` | no delete, deliberately |
| `GET`/`POST /users`, `GET`/`PATCH /users/{id}` | admin accounts, on a two-tier hierarchy |
| `PATCH /users/{id}/activate`, `/deactivate` | deactivating signs them out everywhere |
| `GET /timezones` | the picker's list — **PHP's**, not Python's |
| `GET`/`POST /academic-years`, `…/{id}`, `…/{id}/set-current` | one year is current per school |
| `GET`/`POST /departments`, `/subjects`, and their `{id}` routes | academic configuration |
| `GET`/`POST /classes`, `…/{id}/sections`, `/sections/{id}` | a class carries its sections |
| `GET`/`POST /periods`, `/holidays`, and their `{id}` routes | the school day and the calendar |
| `GET`/`POST /payments`, `…/summary`, `…/{id}`, `…/{id}/receipt` | platform business, Super Admin only |

| File | |
|---|---|
| `school/scope.py` | **`SchoolScope`** — which schools an actor may touch. The most important file here |
| `school/policies.py` | the policy ports; every rule has an ALLOW and a DENY test |
| `school/tokens.py` | Sanctum's token format, issued and accepted |
| `school/hashing.py` | Laravel's bcrypt, at Laravel's cost |
| `school/errors.py` | the `{code, message, details}` envelope, for every path |
| `school/pagination.py` | the `{data, links, meta}` envelope |
| `school/resources.py` | what a record looks like on the wire — every key is contract |
| `school/requests.py` / `validation.py` | the same 422s, in Laravel's own wording |
| `school/fields.py` | the one field that knows a naive column holds UTC — read its docstring |
| `school/zones.py` | the timezone list, generated from PHP because Python's is a different list |
| `school/queue.py` | the job queue — a table and a cron, because the host has no broker |
| `school/receipts.py` | the payment receipt, rendered by `xhtml2pdf` |
| `school/money.py` | every figure a `Decimal`, never a float |
| `school/models.py` | 41 models, all `managed = False` |
| `school/factories.py` | `factory_boy` equivalents of Laravel's factories |
| `config/test_runner.py` | builds the test database from unmanaged models |
| `manage.py check_models` | proves the models still match the real tables |

## Both backends can serve the same session

This is the thing most worth knowing about this directory, and the plan
originally said it was impossible.

A password hashed by PHP verifies in Python and vice versa, and **a token
issued by one backend works on the other** — Sanctum stores a plain SHA-256 of
the token's random half, not a bcrypt digest. So Laravel and Django can answer
for the same signed-in user against the same database at the same time, which
is what makes the cutover a document-root switch that signs nobody out.

`school/tests/test_interop.py` asserts both, against fixed values produced by
the running Laravel app rather than by the Python side.

## Django does not own the schema

Every table already exists, created by Laravel's migrations. M1 proved the
PostgreSQL schema identical to MySQL's, and `schema:diff` still reports no
differences across 47 tables and 486 columns, so
there is nothing for Django to build — and `managed = False` on all 41 models
says so. Every relation is `DO_NOTHING` for the same reason: the foreign keys
carry their own `ON DELETE` rules, enforced by PostgreSQL, and restating them
here would mean keeping one decision in two places.

There is no `migrations/` package, deliberately. An empty one makes Django
treat the app as already migrated and create nothing, which is a confusing way
to find out.

**Two different claims, two different checks, and neither substitutes for the
other:**

- `manage.py test school` builds a test database *from the models* and exercises
  them. It proves the models agree with themselves.
- `manage.py check_models` reads the *real* database, selecting a row from every
  table and touching every field. It proves the models agree with Laravel — and
  it is the one that catches a migration moving underneath them.

**That distinction is not theoretical.** M8 shipped a bug where every timestamp
came back five and a half hours early, and all 156 tests passed — because the
test database's timestamp columns are `timestamptz` (Django built them) while
the real ones are `timestamp without time zone` (Laravel built them), and a
naive datetime takes the machine's local zone when converted. See
`school/fields.py`. The habit that caught it was asking both backends the same
question and diffing the answers, which is worth doing for every module:

```bash
curl -s localhost:8001/api/v1/students -H "Authorization: Bearer $LARAVEL" > a.json
curl -s localhost:8002/api/v1/students -H "Authorization: Bearer $DJANGO"  > b.json
diff <(python -m json.tool --sort-keys a.json) <(python -m json.tool --sort-keys b.json)
```

## Running it

```bash
cd backend-python
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt     # .venv/bin/pip elsewhere

# Reads the same PG_* keys as backend/.env, so the credentials live in one place.
PG_PASSWORD=... .venv/Scripts/python manage.py check_models
PG_PASSWORD=... .venv/Scripts/python manage.py test school

# Its own port, so Laravel on 8000 and the contract instance on 8001 keep running.
PG_PASSWORD=... .venv/Scripts/python manage.py runserver 127.0.0.1:8002

# Deferred work - receipts, and later the messages and bulk imports. Drains
# the queue and exits, which is what makes it safe to run from cron:
#   * * * * * cd /path/to/backend-python && .venv/bin/python manage.py work_queue
PG_PASSWORD=... .venv/Scripts/python manage.py work_queue
```

`check_models` writes nothing. `test` builds and drops its own database and
never touches the one it is pointed at.

To see the Flutter app talk to this backend, build it against the other port —
no source change, just a different define:

```bash
cd frontend
flutter build web --release --output=build/web-python \
  --dart-define=API_BASE_URL=http://127.0.0.1:8002/api/v1
python -m http.server 5001 --directory build/web-python --bind 127.0.0.1
```

Django needs to allow that origin: `DJANGO_CORS_ORIGINS=http://127.0.0.1:5001`.

## What is deliberately absent

No sessions, no CSRF, no admin site, no auth app. This serves a
token-authenticated JSON API to a Flutter client, not HTML to a browser, and
carrying the browser middleware would mean carrying the browser's assumptions.

`SECRET_KEY` has a development default that is useless in production on
purpose: a deployment that forgets to set it should fail loudly rather than run
on a key from a public repository.

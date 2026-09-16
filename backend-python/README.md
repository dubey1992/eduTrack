# The Python backend

Phase M7 onward of [../docs/python-migration.md](../docs/python-migration.md).
Django + DRF, replacing `backend/` — eventually. Until then both run, and
nothing here assumes it owns the database or the port.

## What exists so far

The skeleton, and nothing more. **No endpoints**: those arrive at M8 with auth
and tenancy, then module by module from M9, each landing only when its contract
tests pass ([../contract/README.md](../contract/README.md)).

| | |
|---|---|
| `school/models.py` | 32 models, one per domain table, all `managed = False` |
| `school/factories.py` | `factory_boy` equivalents of Laravel's 31 factories |
| `config/test_runner.py` | builds the test database from unmanaged models |
| `manage.py check_models` | proves the models still match the real tables |

## Django does not own the schema

Every table already exists, created by Laravel's migrations. M1 proved the
PostgreSQL schema identical to MySQL's across 40 tables and 399 columns, so
there is nothing for Django to build — and `managed = False` on all 32 models
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

## Running it

```bash
cd backend-python
python -m venv .venv
.venv/Scripts/pip install -r requirements.txt     # .venv/bin/pip elsewhere

# Reads the same PG_* keys as backend/.env, so the credentials live in one place.
PG_PASSWORD=... .venv/Scripts/python manage.py check_models
PG_PASSWORD=... .venv/Scripts/python manage.py test school
```

`check_models` writes nothing. `test` builds and drops its own database and
never touches the one it is pointed at.

## What is deliberately absent

No sessions, no CSRF, no admin site, no auth app. This serves a
token-authenticated JSON API to a Flutter client, not HTML to a browser, and
carrying the browser middleware would mean carrying the browser's assumptions.

`SECRET_KEY` has a development default that is useless in production on
purpose: a deployment that forgets to set it should fail loudly rather than run
on a key from a public repository.

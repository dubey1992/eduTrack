# Deploying to cPanel

The runbook. Follow it top to bottom the first time; later deploys are just
"Updating an existing deployment" at the end.

Before you start, read **Before you let anyone in**.

**What is being deployed.** The API is the Python backend
(`backend-python/`), running under Passenger as a cPanel Python app, against
PostgreSQL. PHP is still on the host, but only to run migrations: the schema
is Laravel's and migrations are the only way it changes — see
[python-migration.md](python-migration.md). Nothing serves traffic from
`backend/`, and its document root is never pointed at.

## What you need

- cPanel with SSH and cron.
- **Setup Python App** (Passenger), Python 3.11 or newer.
- **PostgreSQL**, with a database and a user you can create.
- PHP 8.3+ and Composer, for migrations only.
- A domain (or subdomain) with HTTPS. Let's Encrypt via cPanel's AutoSSL is
  fine.

Confirmed with the host 2026-10-20: this plan offers both Python and
PostgreSQL. That was the last open question of M0.

## 0. Point the domain at the host

**At the registrar, not in cPanel.** This is the step that looks done when it
is not: cPanel builds a zone for the domain the moment the account exists,
with the apex and every subdomain already pointing at the server — so the
host's own DNS screen reads perfectly while the world still gets the
registrar's parking page. The host's zone is authoritative for nobody until
the registrar sends traffic to it.

Set the domain's nameservers, at whoever it is registered with, to the four
the host's zone declares:

```
in.solidhosting.pro
eu.solidhosting.pro
sg.solidhosting.pro
us.solidhosting.pro
```

Check it from outside, not from cPanel:

```bash
nslookup -type=NS school365ai.com 8.8.8.8     # must list solidhosting.pro
nslookup school365ai.com 8.8.8.8              # must be the server's IP
```

Allow hours for propagation. Until both answer correctly, nothing deployed
below is reachable by name — and AutoSSL cannot issue a certificate either,
because Let's Encrypt validates over the public name.

## 1. Database

Create a PostgreSQL database and a user in cPanel, and grant the user all
privileges on it. Note the name, user and password — cPanel prefixes both
with your account name, e.g. `acct_edutrack` and `acct_edu`.

Nothing else to do here: every table is created by migrations in step 4.

## 2. Files

Put the repository **outside** the web root. Two things on the host use it:
the Python app, whose application root is `backend-python/`, and PHP, which
is only ever run by hand for migrations.

```
/home/<account>/edutrack/                 <- repo, not web-accessible
/home/<account>/edutrack/backend-python/  <- application root for the Python app
/home/<account>/public_html/              <- the Flutter web build (step 6)
```

In **Setup Python App**, create an application with:

| Field | Value |
|---|---|
| Python version | 3.11 or newer |
| Application root | `edutrack/backend-python` |
| Application URL | `api.<domain>` |
| Application startup file | `passenger_wsgi.py` |
| Application Entry point | `application` |

cPanel creates a virtualenv and prints the command that activates it. Use
that command for everything below — the system `python` is not the app's
python, and installing into the wrong one is the single most common way to
spend an hour on this page.

```bash
source /home/<account>/virtualenv/edutrack/backend-python/3.11/bin/activate
cd /home/<account>/edutrack/backend-python
pip install -r requirements.txt
```

Then the PHP side, which runs nothing but migrations:

```bash
cd /home/<account>/edutrack/backend
composer install --no-dev --optimize-autoloader
php artisan key:generate
```

## 3. Configuration

Copy `backend/.env.example` to `backend/.env`. **One file configures both
stacks**: PHP reads it for migrations, and Django reads the same file through
`config/settings.py`, so the two can never be pointed at different databases.
A real environment variable always beats what is written in the file.

The ones that hurt if you get them wrong:

| Setting | Value | Why it matters |
|---|---|---|
| `DJANGO_SECRET_KEY` | 64 random characters | No default outside development. Signs anything the app signs. |
| `DJANGO_ENCRYPTION_KEY` | a Fernet key | Decrypts the stored SMS, WhatsApp and SMTP credentials. **Changing it makes every credential already stored unreadable.** |
| `DJANGO_ALLOWED_HOSTS` | `api.<domain>` | Not a wildcard. |
| `DJANGO_DEBUG` | unset, or `false` | `true` on a public server hands a stack trace, with settings in it, to anyone who can trigger a 500. |
| `PG_*` | from step 1 | Both stacks read these. |
| `DB_CONNECTION` | `pgsql` | What `php artisan migrate` uses. Laravel's `pgsql` connection reads the same `PG_*` keys Django does, so there is nothing to keep in step — but left as `mysql` the migrations land in a database nothing reads. |
| `DJANGO_CACHE_DIR` / `DJANGO_MEDIA_ROOT` | writable, outside the web root | Profile photos are served by an authenticated endpoint, never by the web server. |
| `FRONTEND_URL` | `https://<domain>` | The password-reset link points here. |
| `CORS_ALLOWED_ORIGINS` | the web app's real origin | The example ships `*`. |
| `MAIL_*` | real SMTP | Without it password resets go nowhere and people lock themselves out with no way back. |
| `PLATFORM_TIMEZONE` | e.g. `Asia/Kolkata` | Only the Super Admin's cross-school totals. Each school carries its own — see [timezones.md](timezones.md). |
| `SUPER_ADMIN_EMAIL` / `SUPER_ADMIN_PASSWORD` | the first admin | Used once, in step 4. |

Generate the two keys with the app's own python:

```bash
python -c "import secrets; print(secrets.token_urlsafe(64))"
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Leave `APP_TIMEZONE` alone. It is pinned to UTC in config because every
timestamp column is written in it; changing it silently re-interprets every
row already stored.

## 4. Migrate and create the first Super Admin

**The schema is always Laravel's.** Migrations are the only way it changes,
whichever backend serves the requests.

```bash
cd /home/<account>/edutrack/backend
php artisan migrate --force
```

Then the one account that can onboard the first school:

```bash
cd /home/<account>/edutrack/backend-python
python manage.py create_super_admin
```

It creates exactly one account — the Super Admin from the environment — and
nothing else. It is safe to run again: if the account already exists it is
left untouched, so a password the owner has since changed is never reset back
to whatever the environment happens to say. It will not invent a password,
and it holds the one you give it to the same policy the app enforces on
everybody else.

Then check the two backends agree about the schema they are both looking at:

```bash
python manage.py check_models
```

**Then sign in and change the password**, and clear `SUPER_ADMIN_PASSWORD`
out of `.env`. It has done its job and there is no reason to leave a live
credential sitting in a file.

## 5. Cron

Three jobs. None of them is optional.

```
* * * * * cd /home/<account>/edutrack/backend-python && /home/<account>/virtualenv/edutrack/backend-python/3.11/bin/python manage.py work_queue >> var/queue.log 2>&1
30 2 * * * cd /home/<account>/edutrack/backend-python && /home/<account>/virtualenv/edutrack/backend-python/3.11/bin/python manage.py purge_trip_locations >> var/purge.log 2>&1
0 * * * * cd /home/<account>/edutrack/backend-python && /home/<account>/virtualenv/edutrack/backend-python/3.11/bin/python manage.py close_open_trips >> var/trips.log 2>&1
```

The first drains the job queue — SMS, WhatsApp, announcement fan-out, emailed
reports, payroll runs and the road a bus route follows. It **drains once and
exits** rather than looping, because shared hosting kills a long-running
process and a worker killed mid-job leaves its jobs reserved and unfinished.
Two runs overlapping is safe: reserving a job is a single conditional UPDATE.

The third closes trips nobody ended and tells the school. **Hourly, not
nightly**, because schools keep their own timezones: midnight in Mumbai is
not midnight in Dubai, and a job that ran once a day in one of them would
close the other's trips hours late — or hours early, while a bus was still
out. Without it, a crew member who forgets to end a trip blocks the next
morning's run, and the driver finds that out in a yard at six
(docs/driver-app.md).

The second deletes bus positions older than thirty days. Positions say where
a named attendant was, minute by minute; nobody needs that a month later, so
it is not kept — see [maps.md](maps.md).

Use the **absolute path to the app's python**. Cron does not run the
activation command, and the system python has none of the dependencies.

## 6. The web app

Build with the API base URL pointed at production, then upload
`frontend/build/web/` into `public_html/`:

```bash
cd frontend
flutter build web --release --dart-define=API_BASE_URL=https://api.<domain>/api/v1
```

The app uses hash routing, so no `.htaccess` rewrite rules are needed.

## 7. Restarting the app

Passenger reloads when it is told to, not when files change:

```bash
cd /home/<account>/edutrack/backend-python
mkdir -p tmp && touch tmp/restart.txt
```

cPanel's **Setup Python App** page has a Restart button that does the same
thing. Restart after every `.env` change, every `pip install`, and every
`git pull` — until you do, the old code and the old settings are still live.

There is no equivalent of `config:cache` to re-run. Django reads its settings
at start-up, which is what the restart is for.

## Before you let anyone in

**1. Messages only go where a school has configured them to go.** The
platform ships with a log gateway that records a message as sent without
sending it. Real Twilio and Meta WhatsApp adapters exist, and SMTP is
configured by the Super Admin — but each school's channels are off until
somebody sets them up, and a switched-off channel records nothing at all.
That is the product default, not a gap, and the screens say so. Do not let a
school rely on absence alerts before checking its own channel settings. See
[communication.md](communication.md).

**2. Check `DJANGO_DEBUG` is not `true` on the live site.** Trigger a 404 and
confirm you get the JSON error shape, not a stack trace. The backend refuses
to start without `DJANGO_SECRET_KEY`, so a missing one fails loudly; a
`DJANGO_DEBUG=true` left behind fails silently, which is worse.

**3. Confirm password reset actually sends.** Use the forgot-password flow
with a real address before handing accounts out.

**4. Confirm the queue is running.** File anything that sends a message, then
check `var/queue.log` has moved. A queue nobody drains looks exactly like a
system where nothing is wrong, right up until somebody asks why no alerts
went out.

## Backups

cPanel's own backup covers files. For the database, a nightly dump:

```
30 1 * * * PGPASSWORD='<db_pass>' pg_dump -U <db_user> <db_name> | gzip > /home/<account>/backups/edutrack-$(date +\%F).sql.gz
```

Keep them outside `public_html`, and delete anything older than 30 days.
**Take a dump before every deploy that includes a migration** — that is your
rollback.

## Updating an existing deployment

Anything with migrations in it should happen behind the maintenance page
rather than under people's feet. Set the window first so the page can say
when to come back — see [error-pages.md](error-pages.md).

```bash
cd /home/<account>/edutrack
# take a database dump first if this release has migrations
git pull

cd backend
composer install --no-dev --optimize-autoloader
php artisan migrate --force

cd ../backend-python
pip install -r requirements.txt
python manage.py check_models

mkdir -p tmp && touch tmp/restart.txt
```

`check_models` is cheap and worth running every time: it reads one row of
every table and reports any model that no longer describes the column it is
pointed at, which is how a migration that the Python side has not caught up
with announces itself — before a user finds it.

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

- cPanel with **cron**. SSH if you can get it; the rest of this page assumes
  you cannot, because on the host this was first deployed to, you could not.
- **Setup Python App** (CloudLinux Python Selector), Python 3.11 or newer.
- **PostgreSQL**, with a database and a user you can create.
- **A PHP 8.3+ CLI binary with `pdo_pgsql`**, for migrations only. Not "PHP
  8.3+": see below, because the two are not the same thing.
- A domain (or subdomain) with HTTPS. Let's Encrypt via cPanel's AutoSSL is
  fine, once DNS actually points here.

### What shared hosting will do to you

Written down because every one of these cost an hour, and the next host will
have its own version of each. All were met on one cPanel account in one day.

- **SSH may simply not exist**, whatever the account's feature list says. A
  port that accepts TCP is not SSH: 22222 there is Dovecot, and a key
  imported into cPanel cannot help when nothing is listening.
- **cPanel's Git deployment may be disabled.** `VersionControl/retrieve`
  reports `deployable: 0` and `tasks: []` for a `.cpanel.yml` that is
  valid, parses locally and sits at the checked-out HEAD. Nothing says why.
- **Cron is then the only way to run a command**, which is why
  `scripts/cpanel-deploy.sh` exists and why it takes a lock: scheduled every
  minute, it ran on top of itself and truncated its own log.
- **Long processes get killed.** `pip install -r requirements.txt` died
  partway every time, always around the compiled packages. Install only what
  is missing, one package per call - `scripts/pip_missing.py`.
- **`php` and `composer` on PATH may be CGI wrappers.** A CGI binary answers
  a command line with `Status: 500 Internal Server Error` and an HTML
  content type, and composer refuses outright: *"cannot be run safely on
  non-CLI SAPIs"*. Find a real CLI binary and prove it with `php -v`.
- **The newest PHP is not the one you want, and the oldest is not either.**
  `composer.json` needs ^8.3, so 8.2 is rejected; but of the six builds on
  that host, only **ea-php85** carried `pdo_pgsql`, so every other one
  reached `could not find driver (Connection: pgsql)`. Require both: version
  and driver.
- **PostgreSQL may be older than Django allows.** 10.23 against Django 5.1,
  which demands 13+. `config.legacy_postgresql` lowers that one floor, opt
  in through `PG_ENGINE`, and should be deleted the day the server is
  upgraded.
- **cPanel's file API hides dotfiles** from `Fileman/list_files`. Fetch by
  name instead, or you will conclude that `.env.example` and `.htaccess` are
  missing when they are not.
- **Setup Python App overwrites `passenger_wsgi.py`** with a stub that
  imports itself. Check the file after every Save on that screen.

## 0. Point the domain at the host

**At the registrar, not in cPanel.** This is the step that looks done when it
is not: cPanel builds a zone for the domain the moment the account exists,
with the apex and every subdomain already pointing at the server — so the
host's own DNS screen reads perfectly while the world still gets the
registrar's parking page. The host's zone is authoritative for nobody unless
the registrar delegates to it.

Two ways, and **which one depends on where the domain's DNS actually lives**.
Find out first, and ask the registry rather than a screen:

```bash
curl -s https://rdap.verisign.com/com/v1/domain/<domain> | grep -i ldhName
```

- **The domain uses the registrar's own DNS** (for school365ai.com: GoDaddy,
  `ns15/ns16.domaincontrol.com`). Then leave the nameservers alone and set
  two records in the registrar's DNS panel: `@` → the server's IP, and `api`
  → the same. Remove any domain *forwarding* first — it overrides the A
  record, and it is what serves the parking page.
- **Or delegate the whole domain to the host**, by setting the nameservers to
  the four this host's zone declares: `in.`, `eu.`, `sg.`, `us.solidhosting.pro`.
  More disruptive: every other record (mail especially) moves with it.

Check from outside, and **mind the trailing dot** — without it a resolver may
append a search suffix and answer about an entirely different name, which is
how an hour went missing here:

```bash
nslookup school365ai.com. 8.8.8.8
nslookup api.school365ai.com. 8.8.8.8
```

Allow for propagation. Until both answer with the server's IP, nothing
deployed below is reachable by name — and AutoSSL cannot issue a certificate
either, because Let's Encrypt validates over the public name.

## 1. Database

Create a PostgreSQL database and a user in cPanel, and grant the user all
privileges on it. Note the name, user and password — cPanel prefixes both
with your account name, e.g. `acct_edutrack` and `acct_edu`.

Nothing else to do here: every table is created by migrations in step 4.

## 2. Files

**Where there is no SSH**, which is the case on this host: use cPanel's
**Git™ Version Control** instead of uploading anything. Create a repository
with the clone URL, path `/home/<account>/edutrack`, branch `main`, and the
repository's own `.cpanel.yml` does the install when you click *Deploy HEAD
Commit* — `pip install`, migrations, the first Super Admin, and a Passenger
restart. It is the only supported way to run a command on a host with the
shell switched off, and the file is in the repository where it can be read
rather than hidden in a panel.

Two things `.cpanel.yml` deliberately leaves alone: `public_html`, because
the Flutter build cannot be built on the host and a deploy must never wipe a
working site; and anything secret, because the repository is public — the
`.env` below is uploaded separately.

It also stops, with a line in `~/edutrack-deploy.log`, if the Python app or
`backend/.env` is missing. Read that log after every deploy; a deploy that
did nothing says so there and nowhere else.



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
| `FRONTEND_URL` | `https://<domain>` | The password-reset link points here, as `<domain>/#/reset-password` - the web app routes on the fragment. |
| `DJANGO_CORS_ORIGINS` | the web app's real origin, e.g. `https://school365ai.com,https://www.school365ai.com` | Django's key. It now also honours Laravel's `CORS_ALLOWED_ORIGINS` when its own is unset - but not the example's `*`, which is not an origin. The first live sign-in was CORS-blocked because only the Laravel key was set and Django kept its development default; a `Vary: origin` header with no `Access-Control-Allow-Origin` is what that looks like. |
| `MAIL_*` | real SMTP | Without it password resets go nowhere and people lock themselves out with no way back. |
| `PLATFORM_TIMEZONE` | e.g. `Asia/Kolkata` | Only the Super Admin's cross-school totals. Each school carries its own — see [timezones.md](timezones.md). |
| `SUPER_ADMIN_EMAIL` / `SUPER_ADMIN_PASSWORD` | the first admin | Used once, in step 4. |
| `GOOGLE_MAPS_SERVER_KEY` / `GOOGLE_MAPS_BROWSER_KEY` / `GOOGLE_MAPS_REGION` | the two keys from [maps.md](maps.md) | Without the browser key every map in the web app reads *Map unavailable - no Google Maps key is configured*, because `/api/v1/maps/config` hands it to the app at runtime - it is not baked into the build. This table once left both keys out, and that is exactly what happened on the first live deploy. The browser key's HTTP-referrer restriction in Google Cloud must list the production domain (`https://school365ai.com/*`, `https://www.school365ai.com/*`); the server key's IP restriction must list the host's outbound address, which on shared hosting is not always the address the domain resolves to. |

Generate the two keys with the app's own python:

```bash
python -c "import secrets; print(secrets.token_urlsafe(64))"
python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
```

Leave `APP_TIMEZONE` alone. It is pinned to UTC in config because every
timestamp column is written in it; changing it silently re-interprets every
row already stored.

## 4. Deploy: migrate, and create the first Super Admin

**One command does all of it**, so that a host with no shell can still run
it from cron, and so nobody performs five steps in the wrong order:

```
/bin/bash /home/<account>/edutrack/scripts/cpanel-deploy.sh
```

Add it as a cron job (**Every 5 Minutes** while deploying), watch
`~/edutrack-deploy.log`, and **delete the cron once it reports done**. It
takes a lock, so a schedule that fires while it is still working does no
harm - later runs log `skipped` and exit.

In order, it: installs whatever Python requirements are missing; dumps the
database if there is anything in it; finds a PHP 8.3+ CLI binary that has
`pdo_pgsql`; runs `composer install --no-dev`; runs `php artisan migrate
--force`; creates the Super Admin; runs `check_models`; restarts Passenger;
and finally calls the WSGI application directly to see whether it answers.

**Read the last line of the log, not the middle.** It is either

```
== done ==
```

or

```
== done, WITH 3 FAILED STEP(S) - search the log for FAILED ==
```

The distinction exists because the first real deployment of this project
wrote `== done ==` after every step inside it had failed, and nobody noticed
until 59 tables turned out to be missing.

**The schema is always Laravel's.** Django's models are `managed = False`;
migrations are the only way the schema changes, whichever backend serves the
requests. That is why a PHP binary is needed at all, and the only thing it
is needed for.

**Creating the Super Admin is safe to repeat.** An account that already
exists is left untouched, so a password its owner has since changed is never
reset back to whatever the environment says. It will not invent a password,
and it holds the one you give it to the policy the app enforces on everybody
else.

**Then sign in, change the password, and clear `SUPER_ADMIN_PASSWORD` out of
`.env`.** It has done its job and there is no reason to leave a live
credential in a file.

### When the API returns 404 and nothing is in the log

Decide whose fault it is before opening a ticket or changing code:

```
/home/<account>/edutrack/scripts/check_wsgi.py
```

It calls the WSGI object directly, touching no network. A status line means
the application is fine and the web server is not routing to it - a support
ticket, not a code change. A traceback means it is yours.

### When Passenger never starts the app: the CGI fallback

On the production host, LiteSpeed serves the API subdomain's document root
as plain files and never starts the Python application, whatever the
`.htaccess` says - while `check_wsgi.py` gets 200 from the same application.
If the host cannot or will not enable Passenger, the API can run as **CGI**
instead, which every shared host supports because PHP once needed it:

```
/bin/bash /home/<account>/edutrack/scripts/install-cgi-fallback.sh
```

Run once, from cron. It installs `backend-python/cgi/api.cgi.template` into
the subdomain's `cgi-bin` with the virtualenv's python as its shebang,
proves the script answers 200 when run directly, and only then puts a
rewrite rule in front of everything in that docroot's `.htaccess`. The
previous `.htaccess` is backed up by name in `~/backups/`; restoring it is
the whole undo.

**It is slow.** A fresh interpreter and a fresh Django per request - one to
three seconds before the first byte - and the portal makes several requests
a screen. A bridge, not a destination: the day Passenger works, remove the
block the script adds and the app is served properly.

## 5. Cron

Three jobs. None of them is optional.

```
* * * * * cd /home/<account>/edutrack/backend-python && /home/<account>/virtualenv/edutrack/backend-python/<version>/bin/python manage.py work_queue >> var/queue.log 2>&1
30 2 * * * cd /home/<account>/edutrack/backend-python && /home/<account>/virtualenv/edutrack/backend-python/<version>/bin/python manage.py purge_trip_locations >> var/purge.log 2>&1
0 * * * * cd /home/<account>/edutrack/backend-python && /home/<account>/virtualenv/edutrack/backend-python/<version>/bin/python manage.py close_open_trips >> var/trips.log 2>&1
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

Use the **absolute path to the app's python**, and check the version
directory - cPanel offered 3.12 where this page once said 3.11, and a
hardcoded version fails the day the host moves. `ls ~/virtualenv/edutrack/backend-python/`
names it. Cron does not run the activation command, and the system python
has none of the dependencies.

## 6. The web app

Build with the API base URL pointed at production, then upload
`frontend/build/web/` into `public_html/`:

```bash
cd frontend
flutter build web --release --dart-define=API_BASE_URL=https://api.<domain>/api/v1
```

The app uses hash routing, so no routing rules are needed - but the build
does carry an `.htaccess` (`frontend/web/.htaccess`), and uploading it
**replaces** the one in `public_html`. It holds everything that file needs
from us: the HTTP-to-HTTPS redirect and the page's security headers
(docs/security.md). cPanel adds a block of its own for PHP's error log
("cPanel-generated php ini directives"); the site has no PHP, but put that
block back at the end of the uploaded file rather than let it go missing,
so cPanel's MultiPHP screens find what they wrote. The file also sends
plain addresses to the app (2026-10-26): `/privacy`, `/login` and
`/forgot-password` to their pages, `/features`, `/for-schools`,
`/mobile-app` and `/contact` to the homepage at that section, and since
2026-10-27 any other single lowercase word (`/about`, `/terms`, `/careers`)
to the website page of that name (docs/site-pages.md) - which says "not
available" if nobody has written it. Anything else that is not a file goes
to our own `404.html` rather than the host's. Check afterwards that
`http://` still answers 301 and `https://` 200 with a
`Content-Security-Policy` header.

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

**1b. Force HTTPS on the portal's domain.** cPanel → Domains → *Force
HTTPS Redirect*, for the apex and `www`. Without it the portal is also served
over plain HTTP, and a visitor who types the bare domain gets a page whose
origin is `http://` — which the API, correctly, refuses: every call fails as
a CORS error, and it looks exactly like a misconfigured server. The API
subdomain redirects on its own; the portal's does not until this is on.
Check from outside: `curl -sI http://<domain>/` must answer `301` with a
`Location:` of `https://`.

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

**With a shell**, it is a pull and the deploy script:

```bash
cd /home/<account>/edutrack && git pull
/bin/bash scripts/cpanel-deploy.sh
```

**Without one** - which is the case on this host - pull through cPanel's
**Git™ Version Control → Update from Remote**, then let the deploy cron run
once, then delete the cron again. The script takes the dump, installs what
is missing, migrates, and restarts; it is the same path a first deployment
takes, which is deliberate. There is no second procedure to keep in step
with this one.

`check_models` is cheap and worth running every time: it reads one row of
every table and reports any model that no longer describes the column it is
pointed at, which is how a migration that the Python side has not caught up
with announces itself — before a user finds it.

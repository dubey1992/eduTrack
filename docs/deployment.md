# Deploying to cPanel

The pilot runbook. Follow it top to bottom the first time; later deploys are
just "Updating an existing deployment" at the end.

Before you start, read **Before you let anyone in** — two of those items are
the difference between a demo and a security incident.

## What you need

- cPanel with SSH, PHP 8.3+, MySQL 8, and cron.
- A domain (or subdomain) with HTTPS. Let's Encrypt via cPanel's AutoSSL is
  fine.
- Composer available on the host, or a `vendor/` folder built locally and
  uploaded.

## 1. Database

Create a database and a user in cPanel, and grant the user all privileges on
it. Note the name, user and password — cPanel prefixes both with your account
name, e.g. `acct_edutrack` and `acct_edu`.

Nothing else to do here: every table is created by migrations in step 4.

## 2. Files

Put the Laravel app **outside** the web root, and point the domain's document
root at `backend/public`. Never expose `backend/` itself — `.env` sits in it.

```
/home/<account>/edutrack/          <- repo, not web-accessible
/home/<account>/edutrack/backend/public   <- document root for api.<domain>
/home/<account>/public_html/       <- the Flutter web build (see step 6)
```

```bash
cd /home/<account>/edutrack/backend
composer install --no-dev --optimize-autoloader
php artisan key:generate
```

## 3. Configuration

Copy `.env.example` to `.env` and set at least these. The first four are the
ones that hurt if you get them wrong.

| Setting | Value | Why it matters |
|---|---|---|
| `APP_ENV` | `production` | |
| `APP_DEBUG` | `false` | Leaving it `true` shows a stack trace, with database credentials in it, to anyone who triggers an error. |
| `APP_KEY` | from `key:generate` | Without it, sessions and tokens are not encrypted. |
| `CORS_ALLOWED_ORIGINS` | the web app's real origin | The example ships `*`. |
| `APP_URL` | `https://api.<domain>` | |
| `FRONTEND_URL` | `https://<domain>` | The password-reset link points here. |
| `DB_*` | from step 1 | |
| `MAIL_*` | real SMTP | Defaults to `log`, which means password resets go nowhere and users lock themselves out with no way back. |
| `QUEUE_CONNECTION` | `database` | See step 5. |
| `PLATFORM_TIMEZONE` | e.g. `Asia/Kolkata` | Only the Super Admin's cross-school totals. Each school carries its own — see [timezones.md](timezones.md). |
| `SMS_GATEWAY` | `log` until a provider is signed | See **Before you let anyone in**. |
| `SUPER_ADMIN_EMAIL` / `SUPER_ADMIN_PASSWORD` | the first admin | Used once, in step 4. |

Leave `APP_TIMEZONE` alone. It is pinned to UTC in config because PHP writes
every timestamp column in it; changing it silently re-interprets every row
already stored.

## 4. Migrate and create the first Super Admin

```bash
php artisan migrate --force
php artisan db:seed --force
```

The seeder creates exactly one account — the Super Admin from `.env` — and
nothing else. It is safe to run again: if the account already exists it is
left untouched, so a password the owner has since changed is never reset.

**Then sign in and change the password**, and clear `SUPER_ADMIN_PASSWORD`
out of `.env`. It has done its job and there is no reason to leave a live
credential sitting in a file.

## 5. The queue

SMS and announcement fan-out run on a queue so they never hold up the person
who triggered them. On shared hosting there is no daemon, so cron does it.
Once a minute is enough:

```
* * * * * cd /home/<account>/edutrack/backend && php artisan queue:work --stop-when-empty --max-time=50 >> storage/logs/queue.log 2>&1
```

`--stop-when-empty` and `--max-time=50` keep a run inside its minute so two
never overlap. If the host forbids cron entirely, set `QUEUE_CONNECTION=sync`
— messages then send inline and the request is slower, but nothing is lost.

## 6. The web app

Build with the API base URL pointed at production, then upload
`frontend/build/web/` into `public_html/`:

```bash
cd frontend
flutter build web --release --dart-define=API_BASE_URL=https://api.<domain>/api/v1
```

The app uses hash routing, so no `.htaccess` rewrite rules are needed.

## 7. Permissions and caches

```bash
chmod -R 775 storage bootstrap/cache
php artisan config:cache
php artisan route:cache
```

Re-run both cache commands after **every** `.env` change, or the old values
stay live.

## Before you let anyone in

Four things to check, in order of how much they hurt.

**1. No text message is actually delivered yet.** The only SMS gateway
installed is the demo one, which writes messages to a log and records them as
*Sent*. The Communication Center and Announcements screens show a red warning
saying so, and it disappears by itself once a real gateway is configured. Do
not let anyone rely on absence alerts until then. To add a provider, see
"Adding a real provider" in [communication.md](communication.md).

**2. There is no audit log.** Attendance edits, leave approvals and payment
changes are not recorded anywhere. That is a deliberate choice for the pilot
(it is Phase 21), but it means this period cannot be reconstructed later, so
pilot data should not become the school's permanent historical record.

**3. Check `APP_DEBUG=false` on the live site.** Trigger a 404 and confirm you
get the JSON error shape, not a stack trace.

**4. Confirm password reset actually sends.** Use the forgot-password flow
with a real address before handing accounts out.

## Backups

cPanel's own backup covers files. For the database, a nightly dump is enough
at pilot size:

```
30 1 * * * mysqldump -u <db_user> -p'<db_pass>' <db_name> | gzip > /home/<account>/backups/edutrack-$(date +\%F).sql.gz
```

Keep them outside `public_html`, and delete anything older than 30 days.
**Take a dump before every deploy that includes a migration** — that is your
rollback.

## Updating an existing deployment

Anything with migrations in it should happen behind the maintenance page
rather than under people's feet. Set the window first so the page can say
when to come back - see [error-pages.md](error-pages.md):

```bash
cd /home/<account>/edutrack/backend
# in .env:  MAINTENANCE_UNTIL="2026-09-15 18:00"
php artisan down --retry=60
```

Then:

```bash
cd /home/<account>/edutrack
# take a database dump first if this release has migrations
git pull
cd backend
composer install --no-dev --optimize-autoloader
php artisan migrate --force
php artisan config:cache && php artisan route:cache
```

Then rebuild the web app (step 6) and replace `public_html/`, and let people
back in:

```bash
cd /home/<account>/edutrack/backend
php artisan up
```

The web app is served from `public_html/` and keeps working while the API is
down; the app notices the 503 and holds everyone on its own maintenance
screen until the API answers again. Point Apache's 404 at the page that ships
with the build while you are in there:

```apache
ErrorDocument 404 /404.html
```

Rolling back means restoring the dump and checking out the previous tag.
Migrations are not reversed automatically — `migrate:rollback` exists but has
not been exercised here, so treat the dump as the real safety net.

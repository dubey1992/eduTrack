#!/bin/bash
# Installs the backend on the cPanel host (docs/deployment.md).
#
# Run by .cpanel.yml when somebody clicks "Deploy HEAD Commit". The logic
# lives here rather than as tasks in the YAML for two reasons: cPanel's
# deployment parser is fussy about shell constructs and rejects a whole file
# silently when it dislikes one line, and a script in the repository can be
# read, reviewed and tested like any other code.
#
# **This file is public.** The repository is public on GitHub, so nothing
# here may ever be a credential. Everything secret is in backend/.env, which
# is gitignored and uploaded to the server separately.
#
# What it deliberately does NOT do: touch public_html. The Flutter web build
# is uploaded there directly, cannot be built on this host, and a deploy must
# never wipe a working site because a Dart toolchain is missing.

HOME_DIR="$(cd ~ && pwd)"
REPO="$HOME_DIR/edutrack"
LOG="$HOME_DIR/edutrack-deploy.log"
ENV_FILE="$REPO/backend/.env"
LOCK="$HOME_DIR/edutrack-deploy.lock"

# One at a time, always. This runs from cron on a host with no shell, and
# the first attempt was scheduled every minute: pip was still downloading
# over a slow link when the next run started a second install into the same
# virtualenv and truncated the log underneath it. mkdir is the lock because
# it is atomic everywhere, unlike "test -f then touch".
if ! mkdir "$LOCK" 2>/dev/null; then
  echo "[$(date '+%H:%M:%S')] another deploy is still running - skipped" >> "$LOG"
  exit 0
fi
trap 'rmdir "$LOCK" 2>/dev/null' EXIT

# Counted, because the first real deploy wrote "== done ==" after every
# single step inside it had failed - migrations, Super Admin and all 59
# tables - and the only way anybody found out was reading 2,000 lines of
# log. A deploy that cannot say whether it worked is worse than one that
# fails loudly.
FAILURES=0

# Runs a step, keeps its output in the log, and remembers if it failed.
step() {
  local name="$1"
  shift
  echo "--- $name ---" >> "$LOG"

  "$@" >> "$LOG" 2>&1
  # Captured immediately. After `if cmd; then ... fi` the $? that follows
  # belongs to the if, not to cmd, and would have reported every failure
  # as "exit 0" - which is the same lie this function exists to stop.
  local status=$?

  [ "$status" -eq 0 ] && return 0

  echo "FAILED: $name (exit $status)" >> "$LOG"
  FAILURES=$((FAILURES + 1))
  return "$status"
}

# Appended, never truncated: a log that starts from nothing on every run
# cannot show what the previous run did, which is the one thing it is for.
date "+== deploy %Y-%m-%d %H:%M:%S ==" >> "$LOG"

# The app's own python, not the system one. cPanel builds the virtualenv
# under a version directory, so it is discovered rather than hardcoded - the
# host offered 3.12 where the runbook assumed 3.11, and a hardcoded path
# would have failed on a detail nobody chose.
VENV_BIN="$(ls -d "$HOME_DIR"/virtualenv/edutrack/backend-python/*/bin 2>/dev/null | head -1)"
echo "virtualenv: ${VENV_BIN:-NOT FOUND}" >> "$LOG"

# Both of these must exist first. Missing either, say so and stop: a
# half-run deploy against an unconfigured database is worse than one that
# refuses, and the log is the only place anybody will find out.
if [ -z "$VENV_BIN" ]; then
  echo "STOP: no Python app yet - create it in Setup Python App, application root edutrack/backend-python" >> "$LOG"
  exit 0
fi

if [ ! -f "$ENV_FILE" ]; then
  echo "STOP: backend/.env is missing - upload it before deploying" >> "$LOG"
  exit 0
fi

# Writable, and outside the web root: profile photos are served by an
# authenticated endpoint, never by the web server.
mkdir -p "$HOME_DIR/var/cache" "$HOME_DIR/var/media" "$HOME_DIR/backups"

# Not `pip install -r requirements.txt`: installing all forty over this
# host's link takes long enough that the process is killed every time,
# always around the compiled ones, and pip starts from the top on the next
# run with no idea it is resuming. pip_missing.py installs only what is
# missing, one package per pip call, so each run converges instead of
# repeating - and a killed run costs one package.
echo "--- pip install (only what is missing) ---" >> "$LOG"
cd "$REPO" || exit 1
"$VENV_BIN/python" scripts/pip_missing.py >> "$LOG" 2>&1
PIP_STATUS=$?

if [ "$PIP_STATUS" -ne 0 ]; then
  echo "STOP: requirements are still incomplete - the next run continues" >> "$LOG"
  exit 0
fi

cd "$REPO/backend-python" || exit 1

# The rollback for every deploy that changes the schema. Skips itself on an
# empty database, and never stops the deploy - see the command's own notes.
echo "--- backup ---" >> "$LOG"
"$VENV_BIN/python" manage.py dump_before_migrate >> "$LOG" 2>&1

# `php` on PATH from cron is the CGI wrapper on this host, and a CGI
# binary answers a command line with "Status: 500 Internal Server Error"
# and an HTML content-type - which is exactly what the first deploy
# logged, and is not a Laravel error at all. The CLI binary has to be
# named explicitly, and its path differs per EasyApache build, so the
# candidates are tried in turn and the choice is logged.
echo "--- php ---" >> "$LOG"
PHP_CLI=""

# Ordered on purpose, and checked by version rather than by existing.
#
# Two traps here, both already paid for: `php` on PATH from cron is this
# host's CGI wrapper, which answers a command line with "Status: 500
# Internal Server Error" instead of running anything; and /usr/local/bin/php
# is 8.2 while composer.json requires ^8.3, so the first binary that merely
# *is* PHP is the wrong one. The composer error that found this was
# "Root composer.json requires php ^8.3 but your php version (8.2.34)".
#
# 8.3 first, not the newest: it is the version the project is built and
# tested against, and a deploy is the wrong place to discover what 8.5
# thinks of Laravel.
for candidate in /opt/cpanel/ea-php83/root/usr/bin/php /opt/alt/php83/usr/bin/php                  /opt/cpanel/ea-php84/root/usr/bin/php /opt/alt/php84/usr/bin/php                  /opt/cpanel/ea-php85/root/usr/bin/php /opt/alt/php85/usr/bin/php                  /usr/local/bin/php /usr/bin/php; do
  [ -x "$candidate" ] || continue

  # PHP_VERSION_ID is 80300 for 8.3.0 - a number, so no string comparison
  # decides that "8.10" is older than "8.9".
  version_id="$("$candidate" -r 'echo PHP_VERSION_ID;' 2>/dev/null)"
  case "$version_id" in
    ''|*[!0-9]*) continue ;;
  esac

  if [ "$version_id" -lt 80300 ]; then
    echo "skipping $candidate (PHP_VERSION_ID $version_id, need 80300+)" >> "$LOG"
    continue
  fi

  # Being new enough is not the same as being able to reach the database.
  # ea-php83 here is 8.3.35 and has no pdo_pgsql, so artisan got as far as
  # "could not find driver (Connection: pgsql)" - a Laravel error that
  # reads like configuration and is actually a missing extension.
  if ! "$candidate" -m 2>/dev/null | grep -qi '^pdo_pgsql$'; then
    echo "skipping $candidate ($version_id, no pdo_pgsql)" >> "$LOG"
    continue
  fi

  PHP_CLI="$candidate"
  break
done

if [ -z "$PHP_CLI" ]; then
  echo "STOP: no PHP 8.3+ binary with pdo_pgsql. The schema cannot be migrated" >> "$LOG"
  echo "      until the host installs the PostgreSQL PDO driver for one of them" >> "$LOG"
  echo "      (ea-php83-php-pgsql, or the alt-php equivalent)." >> "$LOG"
  exit 1
fi

echo "php: $PHP_CLI ($("$PHP_CLI" -r 'echo PHP_VERSION;' 2>/dev/null))" >> "$LOG"

# Laravel's vendor/ is gitignored, as it should be, so a fresh clone has
# no autoloader and `php artisan` dies instantly - printing nothing at
# all, which is exactly how the first run looked like it had migrated.
echo "--- composer ---" >> "$LOG"
cd "$REPO/backend" || exit 1

if [ -f vendor/autoload.php ]; then
  echo "vendor/ already present" >> "$LOG"
else
  # Always the phar, driven by the CLI binary we proved above. The host's
  # /usr/local/bin/composer is a wrapper that starts PHP in CGI mode, and
  # composer refuses that outright: "cannot be run safely on non-CLI SAPIs
  # with register_argc_argv=On". Handing the phar to a real CLI php
  # sidesteps the wrapper entirely.
  if [ ! -f "$HOME_DIR/composer.phar" ]; then
    echo "fetching composer.phar" >> "$LOG"
    "$PHP_CLI" -r "copy('https://getcomposer.org/composer-stable.phar', '$HOME_DIR/composer.phar');" >> "$LOG" 2>&1
  fi

  COMPOSER=""
  if [ -f "$HOME_DIR/composer.phar" ]; then
    COMPOSER="$PHP_CLI $HOME_DIR/composer.phar"
  elif [ -f /usr/local/bin/composer ]; then
    # A last resort, and only through the CLI php for the same reason.
    COMPOSER="$PHP_CLI /usr/local/bin/composer"
  fi

  if [ -z "$COMPOSER" ]; then
    echo "STOP: no composer available" >> "$LOG"
    exit 1
  fi

  echo "composer: $COMPOSER" >> "$LOG"
  # --no-dev: the test packages are not wanted on a live server, and they
  # are most of the download.
  $COMPOSER install --no-dev --no-interaction --prefer-dist --optimize-autoloader >> "$LOG" 2>&1
fi

if [ ! -f vendor/autoload.php ]; then
  echo "STOP: vendor/autoload.php still missing - the next run continues" >> "$LOG"
  exit 0
fi

step "migrate (the schema is Laravel's)" "$PHP_CLI" artisan migrate --force

cd "$REPO/backend-python" || exit 1

# Safe to run again: an account that already exists is left untouched, so a
# password its owner has since changed is never reset back.
step "super admin" "$VENV_BIN/python" manage.py create_super_admin

# The two backends must agree about the schema they are both looking at.
step "check_models" "$VENV_BIN/python" manage.py check_models

# Passenger reloads when this is touched; without it the old code keeps
# serving and a successful deploy looks like it did nothing.
echo "--- restart ---" >> "$LOG"
mkdir -p "$REPO/backend-python/tmp"
touch "$REPO/backend-python/tmp/restart.txt"

# Does the application actually answer? A deploy that installs cleanly and
# leaves a dead site is the failure mode this whole file has been chasing,
# and the web server's 404 cannot tell "app is broken" from "app is never
# called". This calls the WSGI object directly, so the log says which.
cd "$REPO" || exit 1
step "self check" "$VENV_BIN/python" scripts/check_wsgi.py

# Switching the API to CGI is asked for by a marker file, not by a flag in
# this script: a marker is a thing somebody puts there on purpose, once,
# through the file manager - and it is consumed here, so the rewrite of a
# live .htaccess cannot happen twice by accident. The installer has its own
# self-test and refuses to touch .htaccess until the CGI script answers 200.
if [ -f "$HOME_DIR/edutrack-install-cgi" ] && [ ! -f "$HOME_DIR/edutrack-cgi-installed" ]; then
  rm -f "$HOME_DIR/edutrack-install-cgi"
  step "install cgi fallback" /bin/bash "$REPO/scripts/install-cgi-fallback.sh"
fi

# Same shape as the CGI switch: a marker put there on purpose, consumed
# here, and a script that checks its own work and rolls itself back.
if [ -f "$HOME_DIR/edutrack-force-https" ] && [ ! -f "$HOME_DIR/edutrack-https-forced" ]; then
  rm -f "$HOME_DIR/edutrack-force-https"
  step "force https on the portal" /bin/bash "$REPO/scripts/force-https.sh"
fi

if [ "$FAILURES" -eq 0 ]; then
  echo "== done ==" >> "$LOG"
  # A marker that says the install finished, so a repeating cron can be
  # told to leave it alone without anybody reading the log.
  touch "$HOME_DIR/edutrack-deployed"
else
  echo "== done, WITH $FAILURES FAILED STEP(S) - search the log for FAILED ==" >> "$LOG"
  rm -f "$HOME_DIR/edutrack-deployed"
  exit 1
fi

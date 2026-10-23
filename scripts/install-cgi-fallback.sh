#!/bin/bash
# Serves the API as CGI on a host whose Passenger never starts it
# (docs/deployment.md). Run from cron, like everything else on a host with
# no shell:
#
#   /bin/bash /home/<account>/edutrack/scripts/install-cgi-fallback.sh
#
# Deliberately separate from cpanel-deploy.sh. That script is run every five
# minutes while deploying and must stay safe to repeat; this one rewrites the
# API subdomain's .htaccess, which is a decision somebody should make on
# purpose, once, and be able to reverse. To reverse it: restore the backup
# this script names in its log.
#
# What it does: copies backend-python/cgi/api.cgi.template into the API
# docroot's cgi-bin with the virtualenv's python as its shebang, makes it
# executable, and puts a rewrite rule in front of everything else in that
# docroot's .htaccess sending every request to it.

HOME_DIR="$(cd ~ && pwd)"
REPO="$HOME_DIR/edutrack"
LOG="$HOME_DIR/edutrack-deploy.log"
DOCROOT="$HOME_DIR/api.school365ai.com"
STAMP="$(date '+%Y-%m-%d-%H%M')"

echo "== cgi fallback $STAMP ==" >> "$LOG"

VENV_BIN="$(ls -d "$HOME_DIR"/virtualenv/edutrack/backend-python/*/bin 2>/dev/null | head -1)"
if [ -z "$VENV_BIN" ] || [ ! -x "$VENV_BIN/python" ]; then
  echo "STOP: no virtualenv python found" >> "$LOG"
  exit 1
fi

if [ ! -d "$DOCROOT" ]; then
  echo "STOP: $DOCROOT does not exist - is the api subdomain created?" >> "$LOG"
  exit 1
fi

mkdir -p "$DOCROOT/cgi-bin" "$HOME_DIR/backups" "$HOME_DIR/var"

# The shim, with the one path only this host knows.
sed "s|__PYTHON__|$VENV_BIN/python|" "$REPO/backend-python/cgi/api.cgi.template" > "$DOCROOT/cgi-bin/api.cgi"
chmod 755 "$DOCROOT/cgi-bin/api.cgi"
echo "installed $DOCROOT/cgi-bin/api.cgi (python: $VENV_BIN/python)" >> "$LOG"

# Does it run at all, before the web server is pointed at it? The same
# question check_wsgi.py answers, asked of the installed script.
if REQUEST_METHOD=GET PATH_INFO=/api/v1/marketing-content SERVER_NAME=api.school365ai.com \
   SERVER_PORT=443 HTTPS=on HTTP_HOST=api.school365ai.com SCRIPT_NAME=/cgi-bin/api.cgi \
   "$DOCROOT/cgi-bin/api.cgi" 2>>"$LOG" | head -1 | grep -q "200"; then
  echo "self test: the CGI script answers 200" >> "$LOG"
else
  echo "STOP: the CGI script did not answer 200 when run directly - .htaccess left alone" >> "$LOG"
  exit 1
fi

# The rewrite, in front of whatever cPanel put there. Backed up first, by
# name, so undoing this is one copy.
HTACCESS="$DOCROOT/.htaccess"
BACKUP="$HOME_DIR/backups/api.htaccess.$STAMP"
[ -f "$HTACCESS" ] && cp "$HTACCESS" "$BACKUP" && echo "backup: $BACKUP" >> "$LOG"

{
  echo "# BEGIN eduTrack CGI fallback - installed $STAMP by scripts/install-cgi-fallback.sh"
  echo "# Every request goes to the API as a CGI script, because Passenger on this"
  echo "# host never starts the application. Remove this block to go back."
  echo "RewriteEngine On"
  echo "RewriteBase /"
  echo "RewriteCond %{REQUEST_URI} !^/cgi-bin/"
  echo "RewriteCond %{REQUEST_URI} !^/\\.well-known/"
  echo "RewriteRule ^(.*)\$ cgi-bin/api.cgi/\$1 [QSA,L]"
  echo "# END eduTrack CGI fallback"
  echo
  [ -f "$BACKUP" ] && cat "$BACKUP"
} > "$HTACCESS"

echo "rewrite installed in $HTACCESS" >> "$LOG"
touch "$HOME_DIR/edutrack-cgi-installed"
echo "== cgi fallback done ==" >> "$LOG"

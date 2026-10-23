#!/bin/bash
# Forces HTTPS on the portal's domain (docs/deployment.md, "Before you let
# anyone in"). The same rewrite cPanel's own "Force HTTPS Redirect" toggle
# writes - used here because this cPanel version exposes that toggle only
# in the browser, and the account has no shell.
#
# Why it matters: served over plain HTTP, the portal hands the browser an
# http:// origin, and the API refuses it as it should - every call fails as
# a CORS error that looks exactly like a misconfigured server.
#
# **It checks its own work and undoes itself.** After writing the rule it
# asks the live site, from the server, for two things: that plain HTTP now
# answers 301 to https://, and that HTTPS still answers 200. If either is
# wrong - a redirect loop behind the proxy, say - the previous .htaccess is
# put back before this script exits, and the log says so.

HOME_DIR="$(cd ~ && pwd)"
LOG="$HOME_DIR/edutrack-deploy.log"
DOCROOT="$HOME_DIR/public_html"
HTACCESS="$DOCROOT/.htaccess"
STAMP="$(date '+%Y-%m-%d-%H%M')"
BACKUP="$HOME_DIR/backups/portal.htaccess.$STAMP"
DOMAIN="school365ai.com"

echo "== force https $STAMP ==" >> "$LOG"

if grep -q "BEGIN eduTrack force https" "$HTACCESS" 2>/dev/null; then
  echo "already in place - nothing to do" >> "$LOG"
  touch "$HOME_DIR/edutrack-https-forced"
  exit 0
fi

mkdir -p "$HOME_DIR/backups"
[ -f "$HTACCESS" ] && cp "$HTACCESS" "$BACKUP" && echo "backup: $BACKUP" >> "$LOG"

{
  echo "# BEGIN eduTrack force https - installed $STAMP by scripts/force-https.sh"
  echo "# Two conditions, both required: this site sits behind a proxy (Via: Caddy),"
  echo "# so %{HTTPS} alone can read 'off' on a secure request and loop forever."
  echo "RewriteEngine On"
  echo "RewriteCond %{HTTPS} !=on"
  echo "RewriteCond %{HTTP:X-Forwarded-Proto} !=https"
  echo "RewriteCond %{REQUEST_URI} !^/\.well-known/"
  echo "RewriteRule ^(.*)\$ https://%{HTTP_HOST}/\$1 [R=301,L]"
  echo "# END eduTrack force https"
  echo
  [ -f "$BACKUP" ] && cat "$BACKUP"
} > "$HTACCESS"
echo "rule written to $HTACCESS" >> "$LOG"

restore() {
  echo "ROLLBACK: $1" >> "$LOG"
  if [ -f "$BACKUP" ]; then cp "$BACKUP" "$HTACCESS"; else rm -f "$HTACCESS"; fi
  echo "previous .htaccess restored" >> "$LOG"
  exit 1
}

sleep 2
http_status="$(curl -s -o /dev/null -w '%{http_code}' --max-time 20 "http://$DOMAIN/" 2>/dev/null)"
http_location="$(curl -s -o /dev/null -D - --max-time 20 "http://$DOMAIN/" 2>/dev/null | tr -d '\r' | grep -i '^location:' | head -1)"
https_status="$(curl -sk -o /dev/null -w '%{http_code}' --max-time 20 "https://$DOMAIN/" 2>/dev/null)"
echo "check: http -> $http_status ${http_location:-'(no Location)'} | https -> $https_status" >> "$LOG"

[ "$https_status" = "200" ] || restore "https://$DOMAIN/ no longer answers 200 (got $https_status)"
[ "$http_status" = "301" ] || restore "http://$DOMAIN/ did not redirect (got $http_status)"
echo "$http_location" | grep -qi "https://" || restore "the redirect does not point at https://"

touch "$HOME_DIR/edutrack-https-forced"
echo "== force https done ==" >> "$LOG"

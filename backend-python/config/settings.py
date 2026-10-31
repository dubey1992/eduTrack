"""Settings for the Python backend.

Phase M7 of ../docs/python-migration.md. This replaces the Laravel backend in
backend/, and until it does both run side by side - which is why nothing here
assumes it owns the database or the port.

Two things are deliberate and easy to undo by accident:

- **The database is not managed by Django.** Every table already exists and was
  created by Laravel's migrations, and M1 proved the PostgreSQL schema is
  identical to MySQL's down to the last of 399 columns. Django describes those
  tables; it does not own them. `managed = False` on every model says so, and
  the day this backend takes over is the day that changes - deliberately, in
  its own commit, not as a side effect.
- **UTC, everywhere.** eduTrack stores instants in UTC and works out each
  school's local day in application code. A backend that quietly localised
  timestamps would move attendance across a day boundary for any school far
  enough east or west.
"""

import sys
from pathlib import Path
import os

from django.core.exceptions import ImproperlyConfigured
from dotenv import dotenv_values, load_dotenv

from config.cors import allowed_origins

BASE_DIR = Path(__file__).resolve().parent.parent

# `manage.py test`: the suite runs without DEBUG, as production does, but
# keeps some conveniences below that a live server must not have.
#
# Recorded in the environment as well as read from argv, because
# `--parallel` spawns worker processes whose argv is the multiprocessing
# bootstrap, not this command. A worker that did not know it was testing
# would configure itself differently from the run it belongs to, which is a
# very confusing way to lose an afternoon.
TESTING = (len(sys.argv) > 1 and sys.argv[1] == "test") or os.environ.get("EDUTRACK_TESTING") == "1"

if TESTING:
    os.environ["EDUTRACK_TESTING"] = "1"

# One .env, read by both stacks (docs/deployment.md).
#
# The schema stays Laravel's - migrations are the only way it changes - so
# PHP and Python sit on the same host and must not disagree about the
# database they are pointed at, the encryption key, or the first admin's
# address. They read the same file.
#
# Loaded here rather than in manage.py or passenger_wsgi.py, because settings
# is the one place configuration is read and neither of those can forget it.
# **A real environment variable always wins** (override=False): that is what
# keeps CI, the test runner and a one-off `DJANGO_DEBUG=true` in a shell
# working whatever the file happens to say.
ENV_FILE = Path(os.environ.get("EDUTRACK_ENV_FILE") or BASE_DIR.parent / "backend" / ".env")

if ENV_FILE.is_file():
    if TESTING:
        # **The suite does not take configuration from a developer's file.**
        # It once did, for about an hour, and a `.env` with MAIL_PASSWORD in
        # it made a test asserting "nothing is configured" report that
        # something was. A test that answers differently on two machines is
        # worse than no test, and CI has no .env at all - so what passes here
        # has to be what passes there.
        #
        # The database is the exception, and only the database: it is what a
        # local run needs to connect at all, CI sets the same keys itself,
        # and no PG_* value can change what any test asserts.
        for key, value in dotenv_values(ENV_FILE).items():
            if key.startswith("PG_") and value is not None and key not in os.environ:
                os.environ[key] = value
    else:
        load_dotenv(ENV_FILE, override=False)

# Off unless a developer turns it on (Phase 21). DEBUG on a public server hands
# a stack trace, with settings, to anybody who can trigger a 500 - so the safe
# value is the one you get by forgetting to set it. Read after the file, so a
# development .env can turn it on.
DEBUG = os.environ.get("DJANGO_DEBUG", "false").lower() == "true"


# The real one comes from the environment. Outside development and the test
# suite there is no default at all: a deployment that forgets it fails at
# start-up rather than running on a key that is in a public repository.
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY") or ("dev-only-not-for-deployment" if DEBUG or TESTING else "")
if not SECRET_KEY:
    raise ImproperlyConfigured("Set DJANGO_SECRET_KEY (or DJANGO_DEBUG=true for development).")

ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost").split(",")

# Encrypts provider credentials and the SMTP password at rest (school/crypto.py).
# Its own key, not SECRET_KEY, so the two rotate independently. Development
# and the test suite derive one from the throwaway SECRET_KEY; a deployment
# that forgets it fails at start-up, like a missing SECRET_KEY does.
ENCRYPTION_KEY = os.environ.get("DJANGO_ENCRYPTION_KEY", "")

# Google Maps (docs/maps.md). Two keys, never one: the server key does the
# asking - address search, place details, reverse geocoding, road paths -
# and never leaves this process. The browser key only draws maps, is handed
# to signed-in administrators by `GET maps/config`, and is protected by the
# referrer and package restrictions set on it in Google Cloud rather than by
# being secret. With neither set, every map degrades to the list screen it
# sits beside and nothing else breaks.
GOOGLE_MAPS_SERVER_KEY = os.environ.get("GOOGLE_MAPS_SERVER_KEY", "")
GOOGLE_MAPS_BROWSER_KEY = os.environ.get("GOOGLE_MAPS_BROWSER_KEY", "")

# Push notifications (docs/teacher-app.md, T6): the path to the Firebase
# service account key file, kept outside git. Empty means push is off.
FIREBASE_CREDENTIALS_FILE = os.environ.get("FIREBASE_CREDENTIALS_FILE", "")

# Biases address search towards the country the platform is sold in. An
# ISO 3166-1 alpha-2 code, or empty for no bias.
GOOGLE_MAPS_REGION = os.environ.get("GOOGLE_MAPS_REGION", "IN")
if not ENCRYPTION_KEY and not (DEBUG or TESTING):
    raise ImproperlyConfigured("Set DJANGO_ENCRYPTION_KEY (see school/crypto.py for how to generate one).")

INSTALLED_APPS = [
    "django.contrib.contenttypes",
    "django.contrib.auth",
    "django.contrib.staticfiles",
    "rest_framework",
    "corsheaders",
    "school",
]

# No sessions, no CSRF, no messages: this serves a token-authenticated JSON API
# to a Flutter client, not HTML to a browser. Carrying the browser middleware
# would mean carrying the browser's assumptions.
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
    # Above CommonMiddleware, which is where it has to sit: a redirect issued
    # before the CORS headers are attached reaches the browser without them,
    # and the browser reports it as a CORS failure rather than a redirect.
    "corsheaders.middleware.CorsMiddleware",
    "django.middleware.common.CommonMiddleware",
    "django.middleware.clickjacking.XFrameOptionsMiddleware",
    # The API serves JSON, CSV and PDF, never a page: a policy that allows
    # nothing costs nothing and stops a response being framed or scripted.
    "school.security.ContentSecurityPolicyMiddleware",
    # Nothing the API answers belongs in search results (docs/seo.md).
    "school.security.NoIndexMiddleware",
    # Lets the audit trail record where a change came from (school/audit.py).
    "school.audit.AuditContextMiddleware",
]

# -- transport security (Phase 21, docs/security.md) ---------------------------
# On in production, off in development, where the servers are plain HTTP.
SECURE_SSL_REDIRECT = os.environ.get("DJANGO_SSL_REDIRECT", "false" if DEBUG or TESTING else "true").lower() == "true"
SECURE_HSTS_SECONDS = int(os.environ.get("DJANGO_HSTS_SECONDS", "0" if DEBUG or TESTING else "31536000"))
SECURE_CONTENT_TYPE_NOSNIFF = True
SECURE_REFERRER_POLICY = "no-referrer"
X_FRAME_OPTIONS = "DENY"

# `check --deploy` asks for CSRF middleware. It protects cookie sessions, and
# this API has none: every request carries a bearer token a forged cross-site
# request cannot attach. (Its HSTS subdomain and preload warnings are left
# standing on purpose - they depend on the real domain, decided in Phase 22.)
SILENCED_SYSTEM_CHECKS = ["security.W003"]

# Only when the host terminates TLS in a proxy that says so. Trusting this
# header without such a proxy lets any client claim its request was secure.
if os.environ.get("DJANGO_BEHIND_TLS_PROXY", "false").lower() == "true":
    SECURE_PROXY_SSL_HEADER = ("HTTP_X_FORWARDED_PROTO", "https")

# Throttle counts are shared by every server process, so a guesser cannot
# spread attempts across workers - and survive a restart. Files, because the
# host has no Redis; an in-memory cache for the test suite, which clears it.
CACHES = {
    "default": (
        {"BACKEND": "django.core.cache.backends.locmem.LocMemCache"}
        if TESTING
        else {
            "BACKEND": "django.core.cache.backends.filebased.FileBasedCache",
            "LOCATION": os.environ.get("DJANGO_CACHE_DIR", str(BASE_DIR / "var" / "cache")),
        }
    )
}

# Uploaded files - profile photos today (school/photos.py). On local disk,
# under var/ with the other runtime state and outside anything a web server
# serves: a photo is only ever read back through an authenticated endpoint.
# Pointing STORAGES at S3 later needs no code change.
MEDIA_ROOT = os.environ.get("DJANGO_MEDIA_ROOT", str(BASE_DIR / "var" / "media"))
STORAGES = {
    "default": {"BACKEND": "django.core.files.storage.FileSystemStorage"},
    "staticfiles": {"BACKEND": "django.contrib.staticfiles.storage.StaticFilesStorage"},
}

ROOT_URLCONF = "config.urls"
WSGI_APPLICATION = "config.wsgi.application"

TEMPLATES = [
    {
        "BACKEND": "django.template.backends.django.DjangoTemplates",
        "DIRS": [],
        "APP_DIRS": True,
        "OPTIONS": {"context_processors": []},
    },
]

# The same PG_* keys the Laravel side reads, so one .env describes both
# backends and there is no second place to keep the credentials in step.
DATABASES = {
    "default": {
        # The stock backend everywhere, unless the environment names another.
        # The one other is config.legacy_postgresql, which exists solely to
        # lower Django's version floor for a production host still on
        # PostgreSQL 10 - see that module, and delete the setting the day it
        # is upgraded.
        "ENGINE": os.environ.get("PG_ENGINE", "django.db.backends.postgresql"),
        "HOST": os.environ.get("PG_HOST", "127.0.0.1"),
        "PORT": os.environ.get("PG_PORT", "5433"),
        "NAME": os.environ.get("PG_DATABASE", "edutrack"),
        "USER": os.environ.get("PG_USERNAME", "postgres"),
        "PASSWORD": os.environ.get("PG_PASSWORD", ""),
        "TIME_ZONE": "UTC",
    }
}

# The models are unmanaged, so the default runner would build no tables at all
# and every test would fail on a table that is not there. See
# config/test_runner.py - it flips `managed` for the run and puts it back.
TEST_RUNNER = "config.test_runner.UnmanagedModelTestRunner"

AUTH_PASSWORD_VALIDATORS = []

LANGUAGE_CODE = "en-us"

# Not negotiable. See the module docstring and ../docs/timezones.md.
TIME_ZONE = "UTC"
USE_TZ = True

STATIC_URL = "static/"
DEFAULT_AUTO_FIELD = "django.db.models.BigAutoField"

REST_FRAMEWORK = {
    # Page size and the envelope shape are part of the contract the Flutter
    # apps already depend on, so neither is left to a default. The pagination
    # class that produces {data, meta} is written in school/pagination.py
    # rather than configured, because DRF's own shape is {count, next, results}
    # and the client cannot read it.
    "UNAUTHENTICATED_USER": None,
    "DEFAULT_RENDERER_CLASSES": ["rest_framework.renderers.JSONRenderer"],
    "DEFAULT_PARSER_CLASSES": [
        "rest_framework.parsers.JSONParser",
        "rest_framework.parsers.MultiPartParser",
    ],
    # Sanctum's tokens, read by Python. See school/tokens.py - both backends
    # can serve the same signed-in session, which is what makes the cutover
    # reversible without signing anybody out.
    "DEFAULT_AUTHENTICATION_CLASSES": [
        "school.authentication.SanctumTokenAuthentication",
    ],
    # Every error in the {code, message, details} envelope, which is what the
    # Flutter client parses. A DRF default reaching the client unshaped is a
    # contract break, so this is not optional decoration.
    "EXCEPTION_HANDLER": "school.errors.handler",
    "DEFAULT_PAGINATION_CLASS": "school.pagination.LaravelPagination",
    "PAGE_SIZE": 20,
    # `?format=` is DRF's renderer override by default, which would answer a
    # report's `?format=csv` with a 404 before the view ran. The API has one
    # renderer, and `format` is the reports' own parameter, as it is Laravel's.
    "URL_FORMAT_OVERRIDE": None,
    # Who a throttle is counting (Phase 21). DRF's default trusts the whole
    # X-Forwarded-For header, which the client writes - one invented address
    # per request and the sign-in throttle never fires. Zero proxies means the
    # connection's own address; set DJANGO_NUM_PROXIES to the number of proxies
    # the host really has in front of the app.
    "NUM_PROXIES": int(os.environ.get("DJANGO_NUM_PROXIES", "0")),
}

# The Flutter web app is served from a different origin than the API - 5000
# and 8000 in development - so the browser preflights every request. Laravel
# answers those through its own CORS config; this is the same allowance,
# spelled out here rather than inherited.
# Django's key first, then Laravel's; see config/cors.py for why both.
CORS_ALLOWED_ORIGINS = allowed_origins(os.environ)

# Not Django's TIME_ZONE, which must stay UTC because it decides how instants
# are stored. This is the zone the few views that belong to no school are read
# in - a Super Admin's cross-school totals. See school/clock.py.
PLATFORM_TIMEZONE = os.environ.get("PLATFORM_TIMEZONE", "UTC")

# -- mail ---------------------------------------------------------------------
#
# The product's name goes into every email it sends, and the reset link
# points at the Flutter app's own screen, never a page this backend serves.
APP_NAME = os.environ.get("APP_NAME", "School365ai")
FRONTEND_URL = os.environ.get("FRONTEND_URL", "http://localhost:5173")

# -- the public website (docs/seo.md, S2) --------------------------------------
# Where the plain-HTML public pages are written: the web root, on the same
# host. Unset in development and tests, and then nothing is written.
PUBLIC_SITE_DIR = os.environ.get("PUBLIC_SITE_DIR", "")
PUBLIC_SITE_URL = os.environ.get("PUBLIC_SITE_URL", "https://school365ai.com")
# Where those pages' Request a Demo and Join Early Access forms post to.
PUBLIC_API_URL = os.environ.get("PUBLIC_API_URL", "https://api.school365ai.com/api/v1")
DEFAULT_FROM_EMAIL = os.environ.get("MAIL_FROM_ADDRESS", "hello@example.com")

# Printed to the console while developing, as Laravel's `log` mailer writes to
# its log - and real SMTP otherwise. The console copy of a reset email carries
# a live link, which is acceptable on a developer's machine and nowhere else,
# so it is never the default outside DEBUG.
EMAIL_BACKEND = os.environ.get(
    "EMAIL_BACKEND",
    "django.core.mail.backends.console.EmailBackend" if DEBUG else "django.core.mail.backends.smtp.EmailBackend",
)
EMAIL_HOST = os.environ.get("MAIL_HOST", "127.0.0.1")
EMAIL_PORT = int(os.environ.get("MAIL_PORT", "25"))
EMAIL_HOST_USER = os.environ.get("MAIL_USERNAME", "")
EMAIL_HOST_PASSWORD = os.environ.get("MAIL_PASSWORD", "")
# Laravel's MAIL_SCHEME: "smtps" is TLS from the first byte, "smtp" upgrades
# with STARTTLS when the server offers it, as Django's backend does by default.
EMAIL_USE_SSL = os.environ.get("MAIL_SCHEME", "smtp") == "smtps"
EMAIL_USE_TLS = not EMAIL_USE_SSL and os.environ.get("MAIL_ENCRYPTION", "none" if EMAIL_PORT == 25 else "tls") == "tls"
EMAIL_TIMEOUT = 20
MAIL_FROM_NAME = os.environ.get("MAIL_FROM_NAME", APP_NAME)

# These are the fallback. The Super Admin can replace them in the app with a
# row in mail_settings, which school/mailer.py reads first (docs/communication.md).

# Laravel's password broker: a link lasts an hour, and a second one is not
# sent within a minute of the first.
PASSWORD_RESET_EXPIRE_MINUTES = 60

# Sessions (Phase 21, docs/security.md): a sign-in ends after this many days
# without using the app, and this many days after it began regardless.
SESSION_IDLE_DAYS = int(os.environ.get("SESSION_IDLE_DAYS", "7"))
SESSION_MAX_DAYS = int(os.environ.get("SESSION_MAX_DAYS", "30"))

# Account lockout: this many wrong passwords in a row lock sign-in for this
# many minutes.
LOCKOUT_ATTEMPTS = int(os.environ.get("LOCKOUT_ATTEMPTS", "10"))
LOCKOUT_MINUTES = int(os.environ.get("LOCKOUT_MINUTES", "15"))
PASSWORD_RESET_THROTTLE_SECONDS = 60

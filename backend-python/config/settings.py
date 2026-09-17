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

from pathlib import Path
import os

BASE_DIR = Path(__file__).resolve().parent.parent

# Development only. The real one comes from the environment, and there is no
# usable default on purpose - a deployment that forgets it should fail loudly
# rather than run on a key that is in a public repository.
SECRET_KEY = os.environ.get("DJANGO_SECRET_KEY", "dev-only-not-for-deployment")

DEBUG = os.environ.get("DJANGO_DEBUG", "true").lower() == "true"

ALLOWED_HOSTS = os.environ.get("DJANGO_ALLOWED_HOSTS", "127.0.0.1,localhost").split(",")

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
]

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
        "ENGINE": "django.db.backends.postgresql",
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
}

# The Flutter web app is served from a different origin than the API - 5000
# and 8000 in development - so the browser preflights every request. Laravel
# answers those through its own CORS config; this is the same allowance,
# spelled out here rather than inherited.
CORS_ALLOWED_ORIGINS = [
    origin
    for origin in os.environ.get(
        "DJANGO_CORS_ORIGINS", "http://127.0.0.1:5000,http://localhost:5000"
    ).split(",")
    if origin
]

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

# Laravel's password broker: a link lasts an hour, and a second one is not
# sent within a minute of the first.
PASSWORD_RESET_EXPIRE_MINUTES = 60
PASSWORD_RESET_THROTTLE_SECONDS = 60

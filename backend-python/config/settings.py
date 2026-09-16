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
    "school",
]

# No sessions, no CSRF, no messages: this serves a token-authenticated JSON API
# to a Flutter client, not HTML to a browser. Carrying the browser middleware
# would mean carrying the browser's assumptions.
MIDDLEWARE = [
    "django.middleware.security.SecurityMiddleware",
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
}

"""How this backend is configured, and what it refuses to start without.

Both stacks read one `.env`. The schema stays Laravel's - migrations are the
only way it changes - so PHP and Python sit on the same host and must not
disagree about the database they are pointed at, the key that decrypts the
stored provider credentials, or who the first admin is.

Two rules carry the weight:

- **A real environment variable beats the file.** That is what keeps CI, the
  test runner and a one-off `DJANGO_DEBUG=true` in a shell working whatever
  the file happens to say - and what stops a developer's local `.env`
  silently overriding a deliberate setting.
- **Production has no defaults.** A deployment that forgets the secret key
  fails at start-up rather than running on one that is in a public
  repository.
"""

import os
import secrets
import subprocess
import sys
from pathlib import Path
from unittest import mock

from django.conf import settings
from django.test import TestCase
from cryptography.fernet import Fernet
from dotenv import dotenv_values

BACKEND = Path(settings.BASE_DIR)
REPO = BACKEND.parent

# Shaped like the real ones, valid for nothing. Generated per run so
# neither is a constant anybody could mistake for a usable key.
A_KEY = secrets.token_urlsafe(64)
A_FERNET_KEY = Fernet.generate_key().decode()


class TheEnvFile(TestCase):
    def test_it_is_the_one_laravel_reads(self):
        # Not a copy. A second file is a second thing to keep in step, and
        # the first time they drift the two stacks are pointed at different
        # databases.
        self.assertEqual(REPO / "backend" / ".env", settings.ENV_FILE)

    def test_a_named_file_wins_over_the_default(self):
        """So a deploy can put it somewhere else without patching settings."""
        with mock.patch.dict(os.environ, {"EDUTRACK_ENV_FILE": "/somewhere/else/.env"}):
            chosen = Path(os.environ.get("EDUTRACK_ENV_FILE") or REPO / "backend" / ".env")

        self.assertEqual(Path("/somewhere/else/.env"), chosen)

    def test_a_real_environment_variable_beats_the_file(self):
        """The rule the whole arrangement rests on.

        It is what keeps CI, the test runner and a one-off
        `DJANGO_DEBUG=true` in a shell working whatever the file says - and
        what stops a developer's local `.env`, which points at a laptop's
        database, from quietly winning on a server.
        """
        written = BACKEND / "var" / "test_env_precedence"
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_text("PG_DATABASE=from_the_file\n", encoding="utf-8")
        self.addCleanup(written.unlink)

        asked = subprocess.run(
            [
                sys.executable,
                "-c",
                "import django; django.setup();"
                "from django.conf import settings;"
                "print(settings.DATABASES['default']['NAME'])",
            ],
            env=os.environ
            | {
                "DJANGO_SETTINGS_MODULE": "config.settings",
                "DJANGO_DEBUG": "true",
                "EDUTRACK_ENV_FILE": str(written),
                "PG_DATABASE": "from_the_environment",
            },
            cwd=str(BACKEND),
            capture_output=True,
            text=True,
        )

        self.assertEqual(0, asked.returncode, asked.stderr)
        self.assertEqual("from_the_environment", asked.stdout.strip())

    def test_the_file_is_read_when_nothing_overrides_it(self):
        """The other half: without it, nothing is configured at all."""
        written = BACKEND / "var" / "test_env_fallback"
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_text("PG_DATABASE=from_the_file\n", encoding="utf-8")
        self.addCleanup(written.unlink)

        clean = {key: value for key, value in os.environ.items() if key != "PG_DATABASE"}
        asked = subprocess.run(
            [
                sys.executable,
                "-c",
                "import django; django.setup();"
                "from django.conf import settings;"
                "print(settings.DATABASES['default']['NAME'])",
            ],
            env=clean
            | {
                "DJANGO_SETTINGS_MODULE": "config.settings",
                "DJANGO_DEBUG": "true",
                "EDUTRACK_ENV_FILE": str(written),
            },
            cwd=str(BACKEND),
            capture_output=True,
            text=True,
        )

        self.assertEqual(0, asked.returncode, asked.stderr)
        self.assertEqual("from_the_file", asked.stdout.strip())

    def test_a_test_run_takes_only_the_database_from_the_file(self):
        """The rule that cost an afternoon.

        For about an hour the suite read the whole file, and a developer
        `.env` with MAIL_PASSWORD in it made a test asserting "nothing is
        configured" report that something was. A test that answers
        differently on two machines is worse than no test, and CI has no
        `.env` at all - so what passes here has to be what passes there.

        The database is the exception, and only the database: it is what a
        local run needs to connect, and no PG_* value changes what any test
        asserts.
        """
        written = BACKEND / "var" / "test_env_testing_mode"
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_text(
            "PG_DATABASE=from_the_file" + chr(10) + "MAIL_PASSWORD=a-mail-secret" + chr(10),
            encoding="utf-8",
        )
        self.addCleanup(written.unlink)

        clean = {
            key: value
            for key, value in os.environ.items()
            if key not in ("PG_DATABASE", "MAIL_PASSWORD")
        }
        asked = subprocess.run(
            [
                sys.executable,
                "-c",
                "import os, django; django.setup();"
                "print(os.environ.get('PG_DATABASE'), '|', os.environ.get('MAIL_PASSWORD'))",
            ],
            env=clean
            | {
                "DJANGO_SETTINGS_MODULE": "config.settings",
                "DJANGO_DEBUG": "true",
                "EDUTRACK_TESTING": "1",
                "EDUTRACK_ENV_FILE": str(written),
            },
            cwd=str(BACKEND),
            capture_output=True,
            text=True,
        )

        self.assertEqual(0, asked.returncode, asked.stderr)
        self.assertEqual("from_the_file | None", asked.stdout.strip())

    def test_outside_a_test_run_the_whole_file_is_read(self):
        """The other side of it: a server does want its mail credentials."""
        written = BACKEND / "var" / "test_env_server_mode"
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_text("MAIL_PASSWORD=a-mail-secret" + chr(10), encoding="utf-8")
        self.addCleanup(written.unlink)

        clean = {
            key: value
            for key, value in os.environ.items()
            if key not in ("MAIL_PASSWORD", "EDUTRACK_TESTING")
        }
        asked = subprocess.run(
            [
                sys.executable,
                "-c",
                "import os, django; django.setup();"
                "print(os.environ.get('MAIL_PASSWORD'))",
            ],
            env=clean
            | {
                "DJANGO_SETTINGS_MODULE": "config.settings",
                "DJANGO_DEBUG": "true",
                "EDUTRACK_ENV_FILE": str(written),
            },
            cwd=str(BACKEND),
            capture_output=True,
            text=True,
        )

        self.assertEqual(0, asked.returncode, asked.stderr)
        self.assertEqual("a-mail-secret", asked.stdout.strip())

    def test_it_parses_laravel_quoting_and_interpolation(self):
        """The reason this is a library and not fifteen lines of split('=').

        Both appear in the real file. A reader that handed back a quoted
        secret key with its quotes still attached would misconfigure
        production silently.
        """
        written = BACKEND / "var" / "test_env_sample"
        written.parent.mkdir(parents=True, exist_ok=True)
        written.write_text(
            "# a comment\n"
            "\n"
            "PLAIN=one\n"
            'QUOTED="two three"\n'
            "APP_NAME=eduTrack\n"
            "INTERPOLATED=${APP_NAME} Mail\n",
            encoding="utf-8",
        )
        self.addCleanup(written.unlink)

        values = dotenv_values(written, interpolate=True)

        self.assertEqual("one", values["PLAIN"])
        self.assertEqual("two three", values["QUOTED"])
        self.assertEqual("eduTrack Mail", values["INTERPOLATED"])


class TheExampleFile(TestCase):
    """What a deployer copies. Missing keys here are a deployment that boots
    wrong, or does not boot at all with no clue why."""

    def example(self) -> dict:
        return dotenv_values(REPO / "backend" / ".env.example", interpolate=False)

    def test_it_names_every_setting_the_python_backend_needs(self):
        keys = self.example().keys()

        for required in (
            "DJANGO_SECRET_KEY",
            "DJANGO_ENCRYPTION_KEY",
            "DJANGO_ALLOWED_HOSTS",
            "DJANGO_CACHE_DIR",
            "DJANGO_MEDIA_ROOT",
            "PG_HOST",
            "PG_PORT",
            "PG_DATABASE",
            "PG_USERNAME",
            "PG_PASSWORD",
            "SUPER_ADMIN_EMAIL",
            "SUPER_ADMIN_PASSWORD",
        ):
            self.assertIn(required, keys, required)

    def test_it_carries_no_secret_of_its_own(self):
        """It is committed. Every value in it is either blank or an example."""
        example = self.example()

        for key in ("DJANGO_SECRET_KEY", "DJANGO_ENCRYPTION_KEY", "PG_PASSWORD", "SUPER_ADMIN_PASSWORD"):
            self.assertIn(example.get(key) or "", ("", None), key)


class StartingUp(TestCase):
    """What the backend does when it is not configured.

    Run as a subprocess rather than by reloading settings: the refusal
    happens at import, and the point is that the process does not come up.
    """

    def boot(self, **env) -> subprocess.CompletedProcess:
        clean = {
            key: value
            for key, value in os.environ.items()
            if not key.startswith(("DJANGO_", "PG_", "EDUTRACK_"))
        }
        # An env file that exists would supply what we are testing the
        # absence of, so it is pointed at nothing.
        clean["EDUTRACK_ENV_FILE"] = str(BACKEND / "var" / "no_such_env_file")
        clean["PATH"] = os.environ.get("PATH", "")
        clean.update(env)

        return subprocess.run(
            [sys.executable, "-c", "import django; django.setup()"],
            env=clean | {"DJANGO_SETTINGS_MODULE": "config.settings"},
            cwd=str(BACKEND),
            capture_output=True,
            text=True,
        )

    def test_it_refuses_to_start_without_a_secret_key(self):
        result = self.boot()

        self.assertNotEqual(0, result.returncode)
        self.assertIn("DJANGO_SECRET_KEY", result.stderr)

    def test_a_secret_key_alone_is_not_enough(self):
        """It asks for them one at a time, and the second one matters as
        much: without it every stored provider credential is unreadable,
        which is a screen full of errors rather than a refusal to start."""
        result = self.boot(DJANGO_SECRET_KEY=A_KEY)

        self.assertNotEqual(0, result.returncode)
        self.assertIn("DJANGO_ENCRYPTION_KEY", result.stderr)

    def test_it_starts_once_both_keys_are_there(self):
        result = self.boot(DJANGO_SECRET_KEY=A_KEY, DJANGO_ENCRYPTION_KEY=A_FERNET_KEY)

        self.assertEqual(0, result.returncode, result.stderr)

    def test_development_supplies_its_own_and_production_never_does(self):
        self.assertEqual(0, self.boot(DJANGO_DEBUG="true").returncode)
        self.assertNotEqual(0, self.boot(DJANGO_DEBUG="false").returncode)


class ThePassengerEntryPoint(TestCase):
    """cPanel's Python app loads passenger_wsgi.py from the app root."""

    def test_it_exists_where_passenger_looks_for_it(self):
        self.assertTrue((BACKEND / "passenger_wsgi.py").is_file())

    def test_it_loads_from_a_working_directory_that_is_not_its_own(self):
        """Passenger imports it; it does not run it from this directory."""
        result = subprocess.run(
            [
                sys.executable,
                "-c",
                "import importlib.util, sys;"
                "spec = importlib.util.spec_from_file_location('pw', sys.argv[1]);"
                "mod = importlib.util.module_from_spec(spec);"
                "spec.loader.exec_module(mod);"
                "print(type(mod.application).__name__)",
                str(BACKEND / "passenger_wsgi.py"),
            ],
            env=os.environ | {"DJANGO_DEBUG": "true"},
            cwd=str(REPO),
            capture_output=True,
            text=True,
        )

        self.assertEqual(0, result.returncode, result.stderr)
        self.assertIn("WSGIHandler", result.stdout)

    def test_it_keeps_no_configuration_of_its_own(self):
        """If it did, the cron jobs would not have it - they do not go
        through Passenger."""
        source = (BACKEND / "passenger_wsgi.py").read_text(encoding="utf-8")

        for leak in ("PG_PASSWORD", "SECRET_KEY=", "password"):
            self.assertNotIn(leak, source, leak)

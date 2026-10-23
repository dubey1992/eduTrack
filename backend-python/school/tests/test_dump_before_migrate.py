"""The dump taken before a migration (docs/deployment.md).

The cPanel deploy step runs this immediately before `php artisan migrate`,
so it is the rollback for every deploy that changes the schema. Two things
carry the weight here, and both are about what it refuses to leave behind:

- it never writes a file it could not finish, because a truncated dump that
  looks like a backup is worse than no backup at all;
- it never stops a deploy. The migration still has to happen on a host with
  no pg_dump; the log says whether a dump exists, and that is the honest
  outcome rather than a failed deploy.
"""

import subprocess
from io import StringIO
from pathlib import Path
from unittest import mock

from django.core.management import call_command
from django.test import TestCase


def run(**patches):
    out = StringIO()
    with mock.patch.multiple("school.management.commands.dump_before_migrate", **patches):
        call_command("dump_before_migrate", stdout=out)
    return out.getvalue()


class DumpBeforeMigrate(TestCase):
    def setUp(self):
        self.target = Path(self.mktemp())

    def mktemp(self):
        import tempfile

        directory = tempfile.mkdtemp()
        self.addCleanup(lambda: __import__("shutil").rmtree(directory, ignore_errors=True))
        return directory

    def test_a_host_without_pg_dump_says_so_and_does_not_fail(self):
        """A deploy must not stop because a backup tool is missing."""
        output = run(shutil=mock.Mock(which=mock.Mock(return_value=None)))

        self.assertIn("pg_dump is not installed", output)

    def test_an_empty_database_is_not_dumped(self):
        """Nothing to lose on the first deploy, and a zero-byte file in the
        backups directory looks like a backup."""
        with (
            mock.patch("school.management.commands.dump_before_migrate.shutil.which", return_value="/usr/bin/pg_dump"),
            mock.patch("school.management.commands.dump_before_migrate.Command._has_tables", return_value=False),
        ):
            out = StringIO()
            call_command("dump_before_migrate", stdout=out)

        self.assertIn("no tables yet", out.getvalue())

    def test_a_dump_that_fails_leaves_no_file_behind(self):
        """The dangerous outcome: pg_dump dies half way and the truncated
        file is mistaken for a backup on the day it is needed."""
        failed = subprocess.CompletedProcess(args=[], returncode=1, stderr=b"connection refused")

        with (
            mock.patch("school.management.commands.dump_before_migrate.shutil.which", return_value="/usr/bin/pg_dump"),
            mock.patch("school.management.commands.dump_before_migrate.Command._has_tables", return_value=True),
            mock.patch("school.management.commands.dump_before_migrate.subprocess.run", return_value=failed),
            mock.patch.dict("os.environ", {"BACKUP_DIR": str(self.target)}),
        ):
            out = StringIO()
            call_command("dump_before_migrate", stdout=out)

        self.assertIn("pg_dump failed", out.getvalue())
        self.assertEqual([], list(self.target.glob("*.sql.gz")), "a failed dump must not leave a file")

    def test_the_password_goes_in_the_environment_not_the_command_line(self):
        """A command line is readable by every other account on a shared
        host; an environment is not."""
        done = subprocess.CompletedProcess(args=[], returncode=0, stderr=b"")
        seen = {}

        def record(command, **kwargs):
            seen["command"] = command
            seen["env"] = kwargs.get("env") or {}
            return done

        with (
            mock.patch("school.management.commands.dump_before_migrate.shutil.which", return_value="/usr/bin/pg_dump"),
            mock.patch("school.management.commands.dump_before_migrate.Command._has_tables", return_value=True),
            mock.patch("school.management.commands.dump_before_migrate.subprocess.run", side_effect=record),
            mock.patch.dict("os.environ", {"BACKUP_DIR": str(self.target)}),
        ):
            call_command("dump_before_migrate", stdout=StringIO())

        self.assertIn("PGPASSWORD", seen["env"])
        self.assertNotIn("--password", seen["command"])
        self.assertIn("--no-password", seen["command"])

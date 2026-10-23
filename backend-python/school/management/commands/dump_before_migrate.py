"""Takes a database dump, so a migration has something to go back to.

    python manage.py dump_before_migrate

Run by the cPanel deploy step before `php artisan migrate --force`
(docs/deployment.md). A dump taken after a migration has gone wrong is not a
backup; this is the one that is.

**Never fatal.** A deploy that stops because the backup tool is missing
helps nobody - the migration is still the thing that has to happen, and the
log says plainly whether a dump exists. So every failure here is reported
and swallowed.

**Nothing to dump on the first deploy.** An empty database has nothing to
lose, and a zero-byte file in the backups directory is worse than no file:
it looks like a backup.
"""

import datetime as dt
import gzip
import os
import shutil
import subprocess
from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand
from django.db import connection

KEEP_DAYS = 30


class Command(BaseCommand):
    help = "Dump the database before a migration, if there is anything in it"

    def handle(self, *args, **options):
        database = settings.DATABASES["default"]

        pg_dump = shutil.which("pg_dump")
        if pg_dump is None:
            self.stdout.write("pg_dump is not installed on this host - no dump taken.")
            return

        if not self._has_tables():
            self.stdout.write("The database has no tables yet - nothing to dump.")
            return

        target = Path(os.environ.get("BACKUP_DIR") or Path.home() / "backups")
        target.mkdir(parents=True, exist_ok=True)
        path = target / f"edutrack-{dt.datetime.now():%Y-%m-%d-%H%M}.sql.gz"

        # The password goes in the environment of the one child process and
        # nowhere else: a command line is readable by every other account on
        # a shared host.
        environment = {**os.environ, "PGPASSWORD": database["PASSWORD"]}
        command = [
            pg_dump,
            "--host", database["HOST"],
            "--port", str(database["PORT"]),
            "--username", database["USER"],
            "--no-password",
            database["NAME"],
        ]

        try:
            with gzip.open(path, "wb") as out:
                finished = subprocess.run(command, stdout=out, stderr=subprocess.PIPE, env=environment, timeout=900)
        except (OSError, subprocess.SubprocessError) as error:
            self.stdout.write(f"Could not run pg_dump: {error} - no dump taken.")
            return

        if finished.returncode != 0:
            # The dump is a truncated file at this point, and a truncated
            # dump that looks like a backup is the dangerous outcome.
            path.unlink(missing_ok=True)
            self.stdout.write(f"pg_dump failed: {finished.stderr.decode(errors='replace').strip()[:300]}")
            return

        self.stdout.write(f"Dumped to {path} ({path.stat().st_size // 1024} KB)")
        self._prune(target)

    @staticmethod
    def _has_tables() -> bool:
        with connection.cursor() as cursor:
            cursor.execute("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'")
            return (cursor.fetchone() or [0])[0] > 0

    def _prune(self, target: Path) -> None:
        """Old dumps are deleted here rather than by a second cron job: the
        thing that makes them is the thing that knows how many there are."""
        cutoff = dt.datetime.now() - dt.timedelta(days=KEEP_DAYS)

        for old in sorted(target.glob("edutrack-*.sql.gz")):
            if dt.datetime.fromtimestamp(old.stat().st_mtime) < cutoff:
                old.unlink(missing_ok=True)
                self.stdout.write(f"Removed {old.name} (older than {KEEP_DAYS} days)")

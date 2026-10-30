"""Writes the public website as plain HTML (docs/seo.md, S2).

    python manage.py build_public_site                 # into PUBLIC_SITE_DIR
    python manage.py build_public_site --to some/dir   # anywhere, to look at
    python manage.py build_public_site --if-configured # the deploy: skip if unset

Publishing the homepage or a Website Page already rewrites the pages; this
is for a deploy, where the templates or styles themselves have changed, and
for the nightly run that keeps the homepage's live figures current. It also
writes the web root's .htaccess, which a publish never touches.
"""

from __future__ import annotations

from pathlib import Path

from django.conf import settings
from django.core.management.base import BaseCommand, CommandError

from school import public_site


class Command(BaseCommand):
    help = "Write the public website's pages, sitemap and .htaccess as plain files."

    def add_arguments(self, parser) -> None:
        parser.add_argument("--to", default=None, help="Write here instead of PUBLIC_SITE_DIR.")
        parser.add_argument(
            "--if-configured", action="store_true", help="Do nothing, successfully, where PUBLIC_SITE_DIR is unset."
        )

    def handle(self, *args, **options) -> None:
        target = options["to"] or getattr(settings, "PUBLIC_SITE_DIR", "")

        if not target:
            if options["if_configured"]:
                self.stdout.write("PUBLIC_SITE_DIR is not set; the public website was not written.")
                return

            raise CommandError("Set PUBLIC_SITE_DIR, or pass --to.")

        written = public_site.build(Path(target), server_files=True)
        self.stdout.write(f"Wrote {len(written)} files to {target}.")

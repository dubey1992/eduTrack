"""Do the models actually describe the tables?

    python manage.py check_models

The M7 acceptance check, and the Python side's answer to Laravel's
`php artisan schema:diff`. These models were generated from the real database
and then edited by hand, which is exactly the situation where a column can be
quietly wrong: Django will happily define a field that does not exist until
something selects it.

So this selects. Counting rows would pass on a model with the wrong columns,
because `count(*)` never names one - it reads a row from every table and
touches every field on it, which is the only thing that proves the description
and the table agree.

Kept rather than thrown away because the tables are still Laravel's, and a
migration there can move underneath these models at any time. This is how that
gets noticed.
"""

from django.apps import apps
from django.core.management.base import BaseCommand
from django.db import connection


class Command(BaseCommand):
    help = "Check every model against the table it describes"

    def handle(self, *args, **options):
        models = sorted(apps.get_app_config("school").get_models(), key=lambda m: m.__name__)
        failures = []
        empty = []

        self.stdout.write(f"Against {connection.settings_dict['NAME']} on {connection.settings_dict['HOST']}:{connection.settings_dict['PORT']}\n")

        for model in models:
            try:
                count = model.objects.count()
                row = model.objects.first()

                if row is None:
                    # An empty table proves the columns exist - the SELECT
                    # named them - but not that they can be read back, so say
                    # so rather than counting it as fully proved.
                    empty.append(model.__name__)
                    self.stdout.write(f"  {model.__name__:<30} {count:>6}  columns ok, no row to read")
                    continue

                for field in model._meta.fields:
                    getattr(row, field.attname)

                self.stdout.write(f"  {model.__name__:<30} {count:>6}  ok")
            except Exception as error:
                message = str(error).split("\n")[0]
                failures.append((model.__name__, message))
                self.stdout.write(self.style.ERROR(f"  {model.__name__:<30}        {message[:70]}"))

        self.stdout.write("")
        self.stdout.write(f"models        : {len(models)}")
        self.stdout.write(f"read a row    : {len(models) - len(failures) - len(empty)}")
        self.stdout.write(f"empty tables  : {len(empty)}")

        if failures:
            self.stdout.write(self.style.ERROR(f"failed        : {len(failures)}"))
            raise SystemExit(1)

        self.stdout.write(self.style.SUCCESS("failed        : 0 - every model describes its table"))

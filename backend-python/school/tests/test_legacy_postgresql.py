"""The backend that lets this run on the host's PostgreSQL 10.

Django 5.1 refuses anything older than 13, and the production host runs
10.23. config.legacy_postgresql lowers that floor and changes nothing else.

What these guard is mostly the *blast radius*: that it is opt-in, that it is
the real backend underneath, and that the floor it sets is the only thing
about it that differs. A version floor quietly lowered everywhere - in CI,
in the test suite, on a developer's machine - would hide the day somebody
pointed this at a server too old to work at all.
"""

from django.test import TestCase

from config.legacy_postgresql import base as legacy
from django.db.backends.postgresql import base as stock


class LegacyPostgresqlBackend(TestCase):
    def test_it_lowers_the_floor_to_what_the_host_actually_runs(self):
        self.assertEqual((10,), legacy.DatabaseFeatures.minimum_database_version)

    def test_and_django_would_otherwise_refuse(self):
        """If Django's own floor ever drops to 10, this whole module can go."""
        self.assertGreater(
            stock.DatabaseWrapper.features_class.minimum_database_version,
            legacy.DatabaseFeatures.minimum_database_version,
            "Django now supports this server; delete config.legacy_postgresql",
        )

    def test_it_is_the_real_backend_underneath(self):
        """Not a reimplementation - everything but the floor is Django's."""
        self.assertTrue(issubclass(legacy.DatabaseWrapper, stock.DatabaseWrapper))
        self.assertTrue(issubclass(legacy.DatabaseFeatures, stock.DatabaseWrapper.features_class))

    def test_the_floor_is_the_only_thing_it_changes(self):
        overridden = {
            name
            for name in vars(legacy.DatabaseFeatures)
            if not name.startswith("__")
        }
        self.assertEqual({"minimum_database_version"}, overridden)

    def test_nothing_uses_it_unless_the_environment_asks(self):
        """Opt-in: the suite, CI and development all run the stock backend,
        so a server too old to work anywhere else still fails loudly."""
        from django.conf import settings

        self.assertEqual("django.db.backends.postgresql", settings.DATABASES["default"]["ENGINE"])

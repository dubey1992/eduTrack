"""A test runner that can build tables it does not own.

The models are `managed = False`, because Laravel's migrations own these tables
and Django has no business creating them (see school/models.py). That is right
for every environment except one: a test database starts empty, and an
unmanaged model means Django creates nothing, so every test fails on a table
that is not there.

So `managed` is flipped to True for the duration of a test run and nowhere
else. The test database is built from the models, torn down afterwards, and the
real database is never touched by any of it.

There is a sharp edge worth stating, because it is the reason this file has a
docstring rather than three lines. **The tables built here come from the
models, and the models were generated from the real schema - so a test passing
proves the models agree with themselves, not that they agree with Laravel.**
`manage.py check_models` is what proves the second thing, by reading the real
database. Both are needed and neither substitutes for the other.
"""

from django.apps import apps
from django.test.runner import DiscoverRunner


class UnmanagedModelTestRunner(DiscoverRunner):
    def setup_test_environment(self, **kwargs):
        self.unmanaged = [
            model
            for model in apps.get_app_config("school").get_models()
            if not model._meta.managed
        ]

        for model in self.unmanaged:
            model._meta.managed = True

        super().setup_test_environment(**kwargs)

    def teardown_test_environment(self, **kwargs):
        super().teardown_test_environment(**kwargs)

        # Put them back. A runner that left them managed would leave any later
        # code in the same process believing Django owns the schema.
        for model in self.unmanaged:
            model._meta.managed = False

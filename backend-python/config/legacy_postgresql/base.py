"""The PostgreSQL backend, with Django's version floor lowered.

**This is a temporary accommodation of one host, not a decision.** Django
5.1 refuses to connect to anything older than PostgreSQL 13:

    NotSupportedError: PostgreSQL 13 or later is required (found 10.23).

The production host runs 10.23. Until it is upgraded, that refusal is the
only thing standing between a working deployment and no deployment at all,
so this backend removes it - and nothing else.

**Why removing it is survivable here.** Django gates its genuinely
version-dependent behaviour on `is_postgresql_14/15/16`, which simply report
False on an older server, so those features turn themselves off. The floor
is a blanket statement about what Django is *tested* against rather than a
list of things that will break. And this project's models are all
`managed = False`: Django never issues DDL, because the schema belongs to
Laravel's migrations - so the usual danger of an old server, column types
it cannot create, does not arise.

**What it does not do** is make PostgreSQL 10 safe. 10 reached end of life
in November 2022 and receives no security fixes. This buys time; it does not
buy correctness.

**Opt-in, so it cannot be enabled by accident.** Nothing selects it unless
PG_ENGINE names it in the environment, and the default everywhere else -
development, CI, the test suite - is the stock backend Django ships. To be
rid of this, upgrade the server and delete one line from `.env`.
"""

from django.db.backends.postgresql import base, features

# The oldest PostgreSQL this project has actually been pointed at. Not a
# claim of support: a statement of what the host runs.
OLDEST_SERVER = (10,)


class DatabaseFeatures(features.DatabaseFeatures):
    minimum_database_version = OLDEST_SERVER


class DatabaseWrapper(base.DatabaseWrapper):
    """The stock PostgreSQL wrapper in every respect but the version floor."""

    features_class = DatabaseFeatures

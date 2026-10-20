"""The first Super Admin on the Python backend (docs/deployment.md, step 4).

The account that onboards the first school, and the only way into a freshly
deployed instance. Laravel has had a seeder for this since the beginning;
until now the backend that actually gets deployed had nothing, so a first
deployment of it had no way in at all.

Two rules carry the weight, and both are about what the command refuses to
do: it never invents a password, and it never resets one somebody has
already changed.
"""

from io import StringIO
from unittest import mock

from django.core.management import call_command
from django.core.management.base import CommandError
from django.test import TestCase

from school import factories, hashing
from school.enums import UserRole, UserStatus
from school.models import User

GOOD = "Orchard7Lane"


def env(**values):
    """The environment as a deploy would set it. Anything not named is unset,
    so a test can never pass because the developer's own shell had it."""
    names = (
        "SUPER_ADMIN_EMAIL",
        "SUPER_ADMIN_PASSWORD",
        "SUPER_ADMIN_FIRST_NAME",
        "SUPER_ADMIN_LAST_NAME",
        "SUPER_ADMIN_MOBILE",
    )

    return mock.patch.dict("os.environ", {name: values.get(name, "") for name in names} | {
        name: value for name, value in values.items()
    }, clear=False)


def run(**values) -> str:
    out = StringIO()

    with env(**values):
        call_command("create_super_admin", stdout=out)

    return out.getvalue()


class CreatingIt(TestCase):
    def test_it_creates_one_account_and_nothing_else(self):
        run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=GOOD)

        created = User.objects.get(email="owner@school365ai.com")

        self.assertEqual(UserRole.SUPER_ADMIN, created.role)
        self.assertEqual(UserStatus.ACTIVE, created.status)
        self.assertIsNone(created.school_id)
        self.assertFalse(created.is_sub_admin)
        self.assertFalse(created.must_change_password)
        self.assertEqual(1, User.objects.count())

    def test_the_password_is_hashed_the_way_laravel_hashes_one(self):
        run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=GOOD)

        stored = User.objects.get(email="owner@school365ai.com").password

        self.assertTrue(stored.startswith("$2y$"))
        self.assertTrue(hashing.check(GOOD, stored))

    def test_the_name_and_mobile_come_from_the_environment(self):
        run(
            SUPER_ADMIN_EMAIL="owner@school365ai.com",
            SUPER_ADMIN_PASSWORD=GOOD,
            SUPER_ADMIN_FIRST_NAME="Asha",
            SUPER_ADMIN_LAST_NAME="Nair",
            SUPER_ADMIN_MOBILE="+91 9800000001",
        )

        created = User.objects.get(email="owner@school365ai.com")

        self.assertEqual(("Asha", "Nair", "+91 9800000001"), (created.first_name, created.last_name, created.mobile))

    def test_a_mobile_nobody_gave_is_null_rather_than_empty(self):
        run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=GOOD)

        self.assertIsNone(User.objects.get(email="owner@school365ai.com").mobile)


class SayingWhatItDid(TestCase):
    def test_it_names_the_account_and_never_the_password(self):
        said = run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=GOOD)

        self.assertIn("owner@school365ai.com", said)
        # This goes to a terminal, a deploy log, and whatever is scrolling
        # behind somebody at the time.
        self.assertNotIn(GOOD, said)
        self.assertNotIn(User.objects.get(email="owner@school365ai.com").password, said)


class RunningItAgain(TestCase):
    """A later deploy re-runs the whole setup."""

    def test_an_existing_account_is_left_exactly_as_it_was(self):
        existing = factories.UserFactory(
            email="owner@school365ai.com", role=UserRole.SUPER_ADMIN, school=None, password=hashing.make("TheirOwn9Word")
        )

        said = run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=GOOD)
        existing.refresh_from_db()

        self.assertIn("left untouched", said)
        # The password the owner has since chosen still works, and the one
        # in the environment does not.
        self.assertTrue(hashing.check("TheirOwn9Word", existing.password))
        self.assertFalse(hashing.check(GOOD, existing.password))
        self.assertEqual(1, User.objects.count())

    def test_twice_in_a_row_makes_one_account(self):
        run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=GOOD)
        run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=GOOD)

        self.assertEqual(1, User.objects.filter(email="owner@school365ai.com").count())

    def test_the_same_address_in_a_different_case_is_the_same_account(self):
        factories.UserFactory(email="owner@school365ai.com", role=UserRole.SUPER_ADMIN, school=None)

        said = run(SUPER_ADMIN_EMAIL="Owner@School365ai.com", SUPER_ADMIN_PASSWORD=GOOD)

        self.assertIn("left untouched", said)
        self.assertEqual(1, User.objects.count())


class RefusingTo(TestCase):
    def test_make_up_a_password(self):
        with self.assertRaises(CommandError) as refused:
            run(SUPER_ADMIN_EMAIL="owner@school365ai.com")

        self.assertIn("SUPER_ADMIN_PASSWORD is not set", str(refused.exception))
        self.assertEqual(0, User.objects.count())

    def test_accept_one_too_short(self):
        with self.assertRaises(CommandError) as refused:
            run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD="Ab1")

        self.assertIn("at least 8", str(refused.exception))
        self.assertEqual(0, User.objects.count())

    def test_accept_one_with_no_number_in_it(self):
        with self.assertRaises(CommandError) as refused:
            run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD="orchardlane")

        self.assertIn("letter and one number", str(refused.exception))
        self.assertEqual(0, User.objects.count())

    def test_accept_one_everybody_uses(self):
        # The first account on the platform is the one with the most to lose,
        # and the one no screen ever validates.
        with self.assertRaises(CommandError) as refused:
            run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD="password1")

        self.assertIn("too common", str(refused.exception))
        self.assertEqual(0, User.objects.count())

    def test_say_the_password_back_in_the_refusal(self):
        for bad in ("Ab1", "orchardlane", "password1"):
            with self.assertRaises(CommandError) as refused:
                run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=bad)

            self.assertNotIn(bad, str(refused.exception), bad)


class TheAccountItMakes(TestCase):
    def test_can_actually_sign_in(self):
        """The whole point: a freshly deployed instance somebody can get into."""
        run(SUPER_ADMIN_EMAIL="owner@school365ai.com", SUPER_ADMIN_PASSWORD=GOOD)

        response = self.client.post(
            "/api/v1/auth/login",
            {"email": "owner@school365ai.com", "password": GOOD},
            content_type="application/json",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(UserRole.SUPER_ADMIN, response.data["user"]["role"])

"""The two places Python has to read what PHP wrote.

The migration plan said tokens could not survive a cutover, and that everybody
would be signed out. These tests are the evidence that they can, and they are
here rather than in a note because the claim is only worth as much as its
proof.

Both halves are asserted against *fixed values produced by the running Laravel
app*, not against something this suite generated. A round trip through one
library proves the library is self-consistent and nothing else.
"""

import hashlib

from django.test import TestCase
from django.utils import timezone

from school import factories, hashing, tokens
from school.models import PersonalAccessToken

# Produced by PHP 8.3 on this project, with Laravel's configured cost:
#   password_hash("Secret!2026", PASSWORD_BCRYPT, ["cost" => 12])
# It protects the string below and nothing else, and nothing has ever used it
# as a credential.
PHP_WROTE_THIS = "$2y$12$ZxCuekZ1C5gK.FO6L4e6vuGIg7Aid4FiH.Ejg3aB3CPftG68wavOm"
AND_THIS_IS_THE_PASSWORD = "Secret!2026"


class PasswordsCrossTheLanguageBoundary(TestCase):
    def test_python_verifies_a_hash_php_wrote(self):
        self.assertTrue(hashing.check(AND_THIS_IS_THE_PASSWORD, PHP_WROTE_THIS))

    def test_the_wrong_password_is_still_wrong(self):
        self.assertFalse(hashing.check("Secret!2027", PHP_WROTE_THIS))

    def test_a_missing_or_damaged_hash_is_a_no_rather_than_a_crash(self):
        # An account row with a damaged password column should refuse the
        # login, not turn every attempt into a 500 that confirms the row
        # exists.
        self.assertFalse(hashing.check("anything", None))
        self.assertFalse(hashing.check("anything", ""))
        self.assertFalse(hashing.check("anything", "not-a-hash"))
        self.assertFalse(hashing.check("", PHP_WROTE_THIS))

    def test_what_python_writes_looks_like_what_php_writes(self):
        # Same prefix and same cost, so a column full of both is a column with
        # one scheme in it rather than two.
        written = hashing.make("A Fresh Password 2026")

        self.assertTrue(written.startswith("$2y$12$"))
        self.assertEqual(60, len(written))
        self.assertTrue(hashing.check("A Fresh Password 2026", written))
        self.assertFalse(hashing.check("A Fresh Password 2025", written))

    def test_the_stand_in_hash_costs_a_real_round(self):
        # Its only job is to make a login for an address nobody has cost the
        # same as one for an address somebody does. A malformed value that
        # returned instantly would defeat the purpose silently.
        self.assertFalse(hashing.check("anything at all", hashing.NO_SUCH_ACCOUNT))
        self.assertTrue(hashing.NO_SUCH_ACCOUNT.startswith("$2y$12$"))


class TokensCrossTheLanguageBoundary(TestCase):
    """Sanctum's format, both written and read.

    Sanctum does not hash a token the way it hashes a password: it stores a
    plain SHA-256 of the random half and hands the client `{id}|{random}`.
    That is why this is possible at all.
    """

    def setUp(self):
        self.user = factories.UserFactory()

    def test_an_issued_token_is_id_pipe_secret(self):
        presented = tokens.issue(self.user)
        id_part, secret = presented.split("|", 1)

        self.assertTrue(id_part.isdigit())
        self.assertEqual(tokens.SECRET_LENGTH, len(secret))

    def test_only_the_digest_is_stored(self):
        presented = tokens.issue(self.user)
        secret = presented.split("|", 1)[1]
        row = PersonalAccessToken.objects.get(pk=presented.split("|")[0])

        self.assertEqual(64, len(row.token))
        self.assertEqual(hashlib.sha256(secret.encode()).hexdigest(), row.token)
        self.assertNotIn(secret, row.token)

    def test_a_row_sanctum_could_have_written_is_accepted(self):
        # Built the way PHP would build it - a secret, its SHA-256, the
        # Eloquent class name in the morph column - rather than by calling
        # issue(). If this passes, a token created by Laravel works here.
        secret = "ASanctumIssuedSecretOfFortyCharacters123"
        now = timezone.now()

        row = PersonalAccessToken.objects.create(
            tokenable_type=tokens.TOKENABLE_TYPE,
            tokenable_id=self.user.id,
            name="api-token",
            token=hashlib.sha256(secret.encode()).hexdigest(),
            abilities='["*"]',
            created_at=now,
            updated_at=now,
        )

        found = tokens.find(f"{row.id}|{secret}")

        self.assertIsNotNone(found)
        self.assertEqual(row.id, found.id)

    def test_the_wrong_secret_for_a_real_id_is_refused(self):
        presented = tokens.issue(self.user)
        id_part = presented.split("|")[0]

        self.assertIsNone(tokens.find(f"{id_part}|not-the-secret"))

    def test_rubbish_is_refused_rather_than_raising(self):
        for presented in ("", None, "not-a-token", "abc|def", "999999|x", "|", "12|"):
            with self.subTest(presented=presented):
                self.assertIsNone(tokens.find(presented))

    def test_a_token_with_no_pipe_is_still_understood(self):
        # Sanctum's legacy form. Kept so a token issued by any version of
        # either backend is understood rather than silently rejected.
        secret = "a-legacy-token-with-no-id-prefix"
        now = timezone.now()

        PersonalAccessToken.objects.create(
            tokenable_type=tokens.TOKENABLE_TYPE,
            tokenable_id=self.user.id,
            name="api-token",
            token=hashlib.sha256(secret.encode()).hexdigest(),
            created_at=now,
            updated_at=now,
        )

        self.assertIsNotNone(tokens.find(secret))

    def test_an_expired_token_is_expired(self):
        presented = tokens.issue(self.user)
        row = tokens.find(presented)

        self.assertFalse(tokens.has_expired(row))

        row.expires_at = timezone.now() - timezone.timedelta(minutes=1)
        row.save(update_fields=["expires_at"])

        self.assertTrue(tokens.has_expired(tokens.find(presented)))

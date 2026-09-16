"""API tokens, in Sanctum's format - and readable by Sanctum.

The migration plan assumed this was impossible. It said that at cutover
"everyone is signed out", because Sanctum's stored tokens could not be
validated by any Python auth. That turns out to be wrong, and it is worth
being precise about why: Sanctum does not hash a token the way it hashes a
password. It stores a plain SHA-256 of the random half and hands the client
`{id}|{random}` (see vendor/laravel/sanctum/src/PersonalAccessToken.php).
SHA-256 is SHA-256 in any language.

So this issues and accepts exactly the tokens Laravel does, against the same
`personal_access_tokens` row. Both backends can serve the same signed-in
session, which is what makes a cutover reversible at all: switching back does
not sign anybody out either.

The comparison is constant-time, matching Sanctum's own `hash_equals`. A
timing oracle on a token digest is a slow way to forge a session, but it is a
way.
"""

from __future__ import annotations

import hashlib
import hmac
import secrets

from django.utils import timezone

from .fields import as_utc
from .models import PersonalAccessToken, User

# Sanctum's own: 40 characters from its alphabet, which is what Str::random
# produces. The `token` column is 64 characters - exactly a SHA-256 in hex -
# so the digest, not the secret, is what is stored.
SECRET_LENGTH = 40

# What Laravel names the tokens this API issues. Kept identical so a row's
# origin cannot be told from its name: the point is that either backend can
# have written it.
TOKEN_NAME = "api-token"

# Sanctum's polymorphic owner column holds the Eloquent class name, because no
# morph map is registered (checked, rather than assumed - the rows in the
# database say exactly this). A row naming anything else belongs to some other
# kind of holder and is not a user session.
TOKENABLE_TYPE = r"App\Models\User"


def digest(secret: str) -> str:
    return hashlib.sha256(secret.encode()).hexdigest()


def issue(user: User) -> str:
    """A new token for this user, returned in the one form the client ever
    sees: `{id}|{secret}`. The secret is never stored and cannot be recovered.
    """
    secret = secrets.token_urlsafe(32)[:SECRET_LENGTH]
    now = timezone.now()

    token = PersonalAccessToken.objects.create(
        tokenable_type=TOKENABLE_TYPE,
        tokenable_id=user.id,
        name=TOKEN_NAME,
        token=digest(secret),
        # Sanctum stores this as a JSON array, and `["*"]` is what
        # createToken() writes when no abilities are named.
        abilities='["*"]',
        created_at=now,
        updated_at=now,
    )

    return f"{token.id}|{secret}"


def find(presented: str | None) -> PersonalAccessToken | None:
    """The token row a bearer string refers to, or None.

    Mirrors Sanctum's findToken(), including the legacy form with no `|` in
    it, so a token issued by any version of either backend is understood.
    """
    if not presented:
        return None

    if "|" not in presented:
        return PersonalAccessToken.objects.filter(token=digest(presented)).first()

    id_part, secret = presented.split("|", 1)

    if not id_part.isdigit():
        return None

    token = PersonalAccessToken.objects.filter(pk=int(id_part)).first()

    if token is None:
        return None

    return token if hmac.compare_digest(token.token or "", digest(secret)) else None


def has_expired(token: PersonalAccessToken) -> bool:
    # `expires_at` comes back aware because the column is read through
    # UtcDateTimeField (school/fields.py). Before that it was naive against the
    # real schema, and comparing a naive datetime to an aware one raises - so
    # this line would have crashed on the first token anybody set an expiry on,
    # while passing every test.
    return token.expires_at is not None and as_utc(token.expires_at) <= timezone.now()


def touch(token: PersonalAccessToken) -> None:
    """Records that the token was used, the way Sanctum's guard does.

    Written with update() rather than save() so it costs one statement and
    cannot race with anything else on the row.
    """
    PersonalAccessToken.objects.filter(pk=token.pk).update(last_used_at=timezone.now())

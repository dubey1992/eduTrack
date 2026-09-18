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

Phase 21 gave sessions an end (docs/security.md): one lasts until it has gone
SESSION_IDLE_DAYS without use, and never beyond SESSION_MAX_DAYS after it
began. Both are measured from the row's own dates, so a token Laravel issued
without an `expires_at` ends on the same terms. And a token is named after the
device it was issued to, so a person can see where they are signed in.
"""

from __future__ import annotations

import datetime as dt
import hashlib
import hmac
import re
import secrets

from django.conf import settings
from django.utils import timezone

from .fields import as_utc
from .models import PersonalAccessToken, User

# Sanctum's own: 40 characters from its alphabet, which is what Str::random
# produces. The `token` column is 64 characters - exactly a SHA-256 in hex -
# so the digest, not the secret, is what is stored.
SECRET_LENGTH = 40

# What Laravel names the tokens it issues. A session from a device that says
# nothing about itself is named this too.
TOKEN_NAME = "api-token"

# Sanctum's polymorphic owner column holds the Eloquent class name, because no
# morph map is registered (checked, rather than assumed - the rows in the
# database say exactly this). A row naming anything else belongs to some other
# kind of holder and is not a user session.
TOKENABLE_TYPE = r"App\Models\User"


def digest(secret: str) -> str:
    return hashlib.sha256(secret.encode()).hexdigest()


def issue(user: User, device: str | None = None) -> str:
    """A new token for this user, returned in the one form the client ever
    sees: `{id}|{secret}`. The secret is never stored and cannot be recovered.

    `device` is the User-Agent it was issued to, kept as a short description
    ("Chrome on Windows") - enough to recognise a session, not a fingerprint.
    """
    secret = secrets.token_urlsafe(32)[:SECRET_LENGTH]
    now = timezone.now()

    token = PersonalAccessToken.objects.create(
        tokenable_type=TOKENABLE_TYPE,
        tokenable_id=user.id,
        name=describe_device(device),
        token=digest(secret),
        # Sanctum stores this as a JSON array, and `["*"]` is what
        # createToken() writes when no abilities are named.
        abilities='["*"]',
        # Sanctum honours this column too, so a session ends on time whichever
        # backend is serving it.
        expires_at=now + dt.timedelta(days=settings.SESSION_MAX_DAYS),
        created_at=now,
        updated_at=now,
    )

    return f"{token.id}|{secret}"


# (pattern, name) pairs, most specific first: Edge and Opera say "Chrome" too.
BROWSERS = [
    (r"Edg/", "Edge"), (r"OPR/|Opera", "Opera"), (r"Chrome/", "Chrome"), (r"Firefox/", "Firefox"),
    (r"Safari/", "Safari"), (r"Dart/", "the app"),
]
SYSTEMS = [
    (r"Android", "Android"), (r"iPhone|iPad|iOS", "iOS"), (r"Windows", "Windows"), (r"Mac OS X|Macintosh", "macOS"),
    (r"Linux", "Linux"),
]


def describe_device(user_agent: str | None) -> str:
    """"Chrome on Windows", "the app on Android" - or TOKEN_NAME when the
    caller said nothing recognisable about itself."""
    if not user_agent:
        return TOKEN_NAME

    browser = next((name for pattern, name in BROWSERS if re.search(pattern, user_agent)), None)
    system = next((name for pattern, name in SYSTEMS if re.search(pattern, user_agent)), None)

    if browser and system:
        return f"{browser} on {system}"

    return browser or system or TOKEN_NAME


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
    """Past its own expiry, idle too long, or simply too old.

    The last two are measured from the row's dates rather than trusting
    `expires_at`, so a token issued before Phase 21 - or by Laravel, which
    leaves it null - ends on the same terms as any other.
    """
    now = timezone.now()

    # `expires_at` comes back aware because the column is read through
    # UtcDateTimeField (school/fields.py). Before that it was naive against the
    # real schema, and comparing a naive datetime to an aware one raises - so
    # this line would have crashed on the first token anybody set an expiry on,
    # while passing every test.
    if token.expires_at is not None and as_utc(token.expires_at) <= now:
        return True

    began = as_utc(token.created_at) if token.created_at else None
    if began is not None and began + dt.timedelta(days=settings.SESSION_MAX_DAYS) <= now:
        return True

    last_seen = as_utc(token.last_used_at) if token.last_used_at else began
    return last_seen is not None and last_seen + dt.timedelta(days=settings.SESSION_IDLE_DAYS) <= now


def sessions_of(user: User):
    """The user's live sessions, most recently used first."""
    rows = PersonalAccessToken.objects.filter(tokenable_type=TOKENABLE_TYPE, tokenable_id=user.id)
    return sorted(
        (row for row in rows if not has_expired(row)),
        key=lambda row: as_utc(row.last_used_at or row.created_at),
        reverse=True,
    )


def revoke_all(user: User, keep: PersonalAccessToken | None = None) -> int:
    """Signs the user out everywhere - except, when given, the session in the
    caller's own hand. Returns how many sessions ended."""
    rows = PersonalAccessToken.objects.filter(tokenable_type=TOKENABLE_TYPE, tokenable_id=user.id)
    if keep is not None:
        rows = rows.exclude(pk=keep.pk)

    deleted, _ = rows.delete()
    return deleted


def touch(token: PersonalAccessToken) -> None:
    """Records that the token was used, the way Sanctum's guard does.

    Written with update() rather than save() so it costs one statement and
    cannot race with anything else on the row.
    """
    PersonalAccessToken.objects.filter(pk=token.pk).update(last_used_at=timezone.now())

"""Passwords, hashed the way Laravel hashes them.

Both backends run against the same `users` table for as long as the rollback
window is open, so a password set by one has to be readable by the other. That
rules out Django's own hashers, whose format (`bcrypt_sha256$...`) Laravel
cannot read at all - what goes in this column is a bare bcrypt digest and
nothing else.

Two details are deliberate:

- **Cost 12**, which is Laravel's configured `bcrypt.rounds` (see
  backend/config/hashing.php). A lower cost would still verify, and would
  quietly weaken every password this backend ever sets.
- **The `$2y$` prefix.** Python's bcrypt writes `$2b$`; PHP writes `$2y$`.
  They are the same algorithm - both are the corrected implementation, and
  each library verifies the other's prefix - but a column where half the rows
  look different invites somebody to conclude there are two schemes here when
  there is one. tests/test_hashing.py asserts the round trip in both
  directions rather than leaving that as a claim.

Nothing here logs, returns or raises with a password in it (CLAUDE.md rule 11).
"""

from __future__ import annotations

import bcrypt

# Laravel's config/hashing.php: 'rounds' => 12.
ROUNDS = 12

# A hash of a value nobody knows, verified against when the email on a login
# belongs to no account. Its only job is to make that path cost the same
# bcrypt round a real account costs, so response time does not say whether an
# address is registered. It is not a credential and unlocks nothing.
NO_SUCH_ACCOUNT = "$2y$12$" + "." * 53


def make(password: str) -> str:
    """Hashes a password for storage in `users.password`."""
    digest = bcrypt.hashpw(password.encode(), bcrypt.gensalt(rounds=ROUNDS)).decode()

    return "$2y$" + digest[4:]


def check(password: str, hashed: str | None) -> bool:
    """Does this password match the stored hash?

    A missing or malformed hash is a no, not an exception: an account row with
    a damaged password column should refuse the login, not turn every attempt
    into a 500 that tells an attacker the row exists.
    """
    if not password or not hashed:
        return False

    try:
        return bcrypt.checkpw(password.encode(), hashed.encode())
    except (ValueError, TypeError):
        return False

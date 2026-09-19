"""Secrets at rest: provider credentials and the SMTP password.

A school's Twilio token or Meta access token is written to a column, and the
database is backed up, copied to laptops and read by support staff. So the
column holds ciphertext, and only this process, holding `DJANGO_ENCRYPTION_KEY`,
can read it back.

Fernet: AES-128-CBC with an HMAC over the result, from the `cryptography`
package. Not the SECRET_KEY, which signs things and is rotated on its own
schedule; a separate key means rotating one never silently breaks the other.
Development and the test suite derive a stable key from the throwaway
SECRET_KEY so nobody has to generate one to run the code; a real deployment
must set its own (docs/security.md).

Generate one with:

    python -c "from cryptography.fernet import Fernet; print(Fernet.generate_key().decode())"
"""

from __future__ import annotations

import base64
import hashlib
import json

from cryptography.fernet import Fernet, InvalidToken
from django.conf import settings

# Marks a value this module wrote, so a column holding plain text from before
# encryption existed - there is none today, but a backup restore could bring
# one - is read as plain text rather than failing as bad ciphertext.
PREFIX = "enc:"


def _fernet() -> Fernet:
    key = settings.ENCRYPTION_KEY

    if not key:
        # Development and tests only; settings.py refuses to start a real
        # deployment without a key, so this is never reached there.
        key = base64.urlsafe_b64encode(hashlib.sha256(settings.SECRET_KEY.encode()).digest())

    return Fernet(key)


def encrypt(text: str) -> str:
    return PREFIX + _fernet().encrypt(text.encode()).decode()


def decrypt(stored: str) -> str:
    """The text that was encrypted.

    Raises CannotDecrypt when the key has changed since it was written: the
    caller decides whether that means "not configured" or an error.
    """
    if not stored.startswith(PREFIX):
        return stored

    try:
        return _fernet().decrypt(stored[len(PREFIX):].encode()).decode()
    except InvalidToken as error:
        raise CannotDecrypt("The stored secret was written with a different DJANGO_ENCRYPTION_KEY.") from error


def encrypt_json(value) -> str:
    return encrypt(json.dumps(value))


def decrypt_json(stored: str | None):
    """A dict, or {} for nothing stored or nothing readable - a credentials
    column that cannot be read is treated as not set up, which is what the
    screen should say, rather than crashing every message the school sends."""
    if not stored:
        return {}

    try:
        return json.loads(decrypt(stored))
    except (CannotDecrypt, ValueError):
        return {}


class CannotDecrypt(Exception):
    pass

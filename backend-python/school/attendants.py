"""Bus Attendant sign-in: the rules, kept in one place (docs/maps.md).

An attendant signs in with a **mobile number and a 4-digit passcode, on a
registered device**. The passcode alone is ten thousand guesses; tied to a
device the school registered, it is useless without the phone it was set on.

- An administrator issues a **one-time setup code** (8 digits, 24 hours).
- On the attendant's phone, mobile + setup code + a new passcode registers
  the device. The device gets a long random secret, kept on the phone; only
  its SHA-256 is stored here.
- From then on, mobile + passcode + that device's secret signs in.
- **5 wrong guesses lock the account** - setup codes and passcodes count
  alike - until an administrator unlocks it. There is no timeout.

Attendants often have no email address. One created without one is given a
placeholder in a reserved domain (`.invalid` can never receive mail), so the
`users.email` column keeps its NOT NULL and UNIQUE rules, and every sender
checks `is_placeholder_email` before trying to send.
"""

from __future__ import annotations

import hashlib
import re
import secrets
import uuid

MAX_ATTEMPTS = 5
SETUP_CODE_HOURS = 24
SETUP_CODE_LENGTH = 8
PASSCODE_PATTERN = re.compile(r"^\d{4}$")
NO_EMAIL_DOMAIN = "no-email.invalid"


def login_mobile(mobile: str | None) -> str | None:
    """"+91 98765 43210" as the sign-in key: a plus and the digits."""
    if not mobile:
        return None

    digits = "".join(character for character in mobile if character.isdigit())

    return f"+{digits}" if digits else None


def placeholder_email() -> str:
    return f"attendant-{uuid.uuid4().hex[:16]}@{NO_EMAIL_DOMAIN}"


def is_placeholder_email(address: str | None) -> bool:
    return bool(address) and address.lower().endswith("@" + NO_EMAIL_DOMAIN)


def new_setup_code() -> str:
    return "".join(secrets.choice("0123456789") for _ in range(SETUP_CODE_LENGTH))


def new_device_secret() -> str:
    return secrets.token_urlsafe(48)


def device_digest(secret: str) -> str:
    return hashlib.sha256(secret.encode()).hexdigest()


def passcode_problem(passcode: str) -> str | None:
    """Why a passcode will not do, or None.

    Four digits is small enough that the obvious ones - one digit four times,
    a straight run up or down - are the first anybody would try.
    """
    if not PASSCODE_PATTERN.match(passcode or ""):
        return "The passcode must be exactly 4 digits."

    if len(set(passcode)) == 1:
        return "Choose a passcode that is not one digit repeated."

    steps = {int(b) - int(a) for a, b in zip(passcode, passcode[1:])}

    if steps in ({1}, {-1}):
        return "Choose a passcode that is not a straight run like 1234."

    return None

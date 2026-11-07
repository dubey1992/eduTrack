"""The Family app's sign-in rules, kept in one place
(docs/parent-student-app.md, Phase F0, decision D1).

A parent signs in with a **mobile number and a 6-digit passcode, on a phone
they registered** - the bus crew's design (school/attendants.py), with three
differences for families:

- The office's **one-time setup code lasts 7 days**, not 24 hours: it goes
  home on a printed letter, and letters take days.
- The **passcode is 6 digits**, not 4: a parent's phone is less controlled
  than a school bus.
- **5 wrong passcodes lock the account for 15 minutes**, then it opens again
  by itself. A million passcodes and a registered phone make that safe, and
  it keeps the school office out of a parent's typing mistakes.

A family session ends after 30 days without use (school/tokens.py), or at
once when the school removes the phone or the guardian.

A family account has no email of its own: like the crew's, it is given a
placeholder in the reserved `.invalid` domain, so `users.email` keeps its
rules and nothing is ever sent to it.
"""

from __future__ import annotations

import re
import uuid

from .attendants import NO_EMAIL_DOMAIN, device_digest, login_mobile, new_device_secret, new_setup_code

MAX_ATTEMPTS = 5
LOCK_MINUTES = 15
SETUP_CODE_DAYS = 7
IDLE_DAYS = 30
PASSCODE_PATTERN = re.compile(r"^\d{6}$")

# How a guardian is related to a student, as the office records it.
RELATIONSHIPS = ("mother", "father", "guardian", "other")

__all__ = [
    "IDLE_DAYS", "LOCK_MINUTES", "MAX_ATTEMPTS", "RELATIONSHIPS", "SETUP_CODE_DAYS", "device_digest",
    "login_mobile", "new_device_secret", "new_setup_code", "passcode_problem", "placeholder_email",
]


def placeholder_email() -> str:
    return f"family-{uuid.uuid4().hex[:16]}@{NO_EMAIL_DOMAIN}"


def passcode_problem(passcode: str) -> str | None:
    """Why a passcode will not do, or None.

    Six digits, and not the ones anybody would try first: one digit six times,
    or a straight run up or down.
    """
    if not PASSCODE_PATTERN.match(passcode or ""):
        return "The passcode must be exactly 6 digits."

    if len(set(passcode)) == 1:
        return "Choose a passcode that is not one digit repeated."

    if passcode in "0123456789" or passcode in "9876543210":
        return "Choose a passcode that is not a straight run of digits."

    return None

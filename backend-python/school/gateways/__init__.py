"""The adapters that hand a message to a provider (docs/communication.md).

CLAUDE.md rule 14: nothing outside this package knows a provider's API. A
module says "send this text to this number" or "send this template to this
number" and gets a Result back; which company carries it is the school's
choice in its settings, and adding a company is a new module here.

Every adapter declares:

- `name`, `label`, `delivers` - what the settings screen shows, and whether a
  "Sent" in the log means a phone actually rang. The demo adapters say False.
- `CREDENTIALS` - the fields a school fills in, each (key, label, secret). A
  secret is never returned by the API once saved.
- `send(...)` or `send_template(...)` - which returns a Result and never
  raises: a provider having a bad morning is a failed message with a reason,
  not a dead worker.
"""

from __future__ import annotations

from dataclasses import dataclass, field


@dataclass(frozen=True)
class Result:
    """What a provider did with one message."""

    accepted: bool
    provider_message_id: str | None = None
    failure_reason: str | None = None


@dataclass(frozen=True)
class Template:
    """A registered WhatsApp template, filled in. `values` are the numbered
    parameters in order - {{1}}, {{2}} on Meta; "1", "2" on Twilio."""

    name: str
    language: str = "en"
    values: list[str] = field(default_factory=list)


def missing_credentials(gateway, credentials: dict | None) -> list[str]:
    """The labels of the fields this gateway needs that the school has not
    filled in - empty when it is ready to send."""
    credentials = credentials or {}

    return [label for key, label, _secret in gateway.CREDENTIALS if not credentials.get(key)]


def digits_only(mobile: str) -> str:
    """"+91 98765 43210" as a provider wants it: no spaces, one leading plus."""
    stripped = "".join(character for character in mobile if character.isdigit())

    return "+" + stripped

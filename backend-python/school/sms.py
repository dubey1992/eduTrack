"""Sending an SMS, through whichever gateway a school has chosen.

CLAUDE.md rule 14: attendance and transport code never depends on a specific
provider. It asks for a gateway by name and gets something with a `send`
method, so swapping Twilio for MSG91 is a new adapter and nothing else.

Two gateways exist: the log gateway - the prototype's "Demo Gateway", which
records the message without calling anybody and **does not deliver** - and
Twilio, which needs the school's own account (school/gateways/twilio.py).
"""

from __future__ import annotations

import logging

from .gateways import Result, missing_credentials  # noqa: F401 - re-exported
from .gateways.log import LogGateway
from .gateways.twilio import TwilioSmsGateway

logger = logging.getLogger(__name__)

GATEWAYS = {LogGateway.name: LogGateway(), TwilioSmsGateway.name: TwilioSmsGateway()}


def resolve(name: str | None) -> str:
    """The gateway that will really be used for a name: itself when it is
    installed, the demo gateway otherwise - the same fallback `gateway()`
    applies to sending, so the label on screen never names a gateway that
    will not be used."""
    return name if name in GATEWAYS else LogGateway.name


def label(name: str | None) -> str:
    return GATEWAYS[resolve(name)].label


def delivers(name: str | None) -> bool:
    return GATEWAYS[resolve(name)].delivers


def available() -> list[dict]:
    """Every installed gateway, for the settings screen's picker."""
    return [{"value": key, "label": gateway.label} for key, gateway in GATEWAYS.items()]


def gateway(name: str | None):
    """The gateway a school asked for, or the demo one.

    A school whose chosen provider has been removed from the build still gets
    its messages recorded honestly, with a warning in the log rather than a
    crash in the worker.
    """
    if name not in GATEWAYS:
        logger.warning("Unknown SMS gateway %r - falling back to the demo gateway", name)

    return GATEWAYS[resolve(name)]

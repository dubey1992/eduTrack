"""Sending an SMS, through whichever gateway a school has chosen.

CLAUDE.md rule 14: attendance and transport code never depends on a specific
provider. It asks for a gateway by name and gets something with a `send`
method, so swapping Twilio for MSG91 is a new adapter and nothing else.

Only the log gateway exists today, which is the prototype's "Demo Gateway": it
records the message and writes it to the log without calling anybody. That is
what development and the tests use, and **it does not deliver**. The product
says so rather than letting a school read "Sent" and assume a parent was told.
"""

from __future__ import annotations

import logging
from dataclasses import dataclass

logger = logging.getLogger(__name__)


@dataclass(frozen=True)
class Result:
    """What a gateway did with one message."""

    accepted: bool
    provider_message_id: str | None = None
    failure_reason: str | None = None


class LogGateway:
    """Writes the message to the log and stops there.

    `delivers` is False and is read by the product to tell a school that
    nothing actually reached a phone. A demo gateway that claimed otherwise
    would be the most dangerous adapter in the codebase.
    """

    name = "log"
    label = "Demo Gateway"
    delivers = False

    def send(self, mobile: str, body: str, sender_id: str | None = None) -> Result:
        # The body can name a child and their movements, so it is logged at
        # debug rather than info and the number is not logged at all.
        logger.debug("SMS via the demo gateway (%s characters)", len(body))

        return Result(accepted=True, provider_message_id=None)


GATEWAYS = {LogGateway.name: LogGateway()}


def gateway(name: str | None):
    """The gateway a school asked for, or the demo one.

    An unknown name falls back rather than raising: a school whose chosen
    provider has been removed from the build should still have its messages
    recorded honestly, not have every send crash.
    """
    if name and name not in GATEWAYS:
        logger.warning("Unknown SMS gateway %r - falling back to the demo gateway", name)

    return GATEWAYS.get(name or LogGateway.name, GATEWAYS[LogGateway.name])

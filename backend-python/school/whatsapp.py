"""Sending a WhatsApp message, through whichever gateway a school has chosen.

The same shape as school/sms.py, with one difference that shapes everything
above it: WhatsApp business messaging refuses free text unless the recipient
wrote first within the last day. So every message the school starts is a
*template* the provider approved beforehand, sent by name with its numbered
parameters filled in (school/gateways/__init__.py, `Template`), and a school
maps each event to one of its templates in the Communication Center.

Gateways: the demo gateway, which does not deliver; Twilio; and Meta's own
Cloud API.
"""

from __future__ import annotations

import logging

from .gateways import Template, missing_credentials  # noqa: F401 - re-exported
from .gateways.log import LogWhatsAppGateway
from .gateways.meta import MetaWhatsAppGateway
from .gateways.twilio import TwilioWhatsAppGateway

logger = logging.getLogger(__name__)

GATEWAYS = {
    LogWhatsAppGateway.name: LogWhatsAppGateway(),
    TwilioWhatsAppGateway.name: TwilioWhatsAppGateway(),
    MetaWhatsAppGateway.name: MetaWhatsAppGateway(),
}


def resolve(name: str | None) -> str:
    return name if name in GATEWAYS else LogWhatsAppGateway.name


def label(name: str | None) -> str:
    return GATEWAYS[resolve(name)].label


def delivers(name: str | None) -> bool:
    return GATEWAYS[resolve(name)].delivers


def available() -> list[dict]:
    return [{"value": key, "label": gateway.label} for key, gateway in GATEWAYS.items()]


def gateway(name: str | None):
    if name not in GATEWAYS:
        logger.warning("Unknown WhatsApp gateway %r - falling back to the demo gateway", name)

    return GATEWAYS[resolve(name)]

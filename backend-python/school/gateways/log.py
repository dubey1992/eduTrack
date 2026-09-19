"""The prototype's "Demo Gateway": records the message and stops there.

What development and the tests use, and **it does not deliver**. `delivers`
is False and the product reads it to tell a school that nothing reached a
phone. A demo adapter that claimed otherwise would be the most dangerous
code in the repository: a school would read "Sent" and assume a parent was
told.
"""

from __future__ import annotations

import logging

from . import Result, Template

logger = logging.getLogger("school.sms")


class LogGateway:
    name = "log"
    label = "Demo Gateway"
    delivers = False
    CREDENTIALS = ()

    def send(self, mobile: str, body: str, sender_id: str | None = None, credentials: dict | None = None) -> Result:
        # The body can name a child and their movements, so it is logged at
        # debug rather than info and the number is not logged at all.
        logger.debug("SMS via the demo gateway (%s characters)", len(body))

        return Result(accepted=True, provider_message_id=None)


class LogWhatsAppGateway:
    name = "log"
    label = "Demo Gateway"
    delivers = False
    CREDENTIALS = ()

    def send_template(self, mobile: str, template: Template, credentials: dict | None = None) -> Result:
        logger.debug("WhatsApp via the demo gateway (template %s, %s values)", template.name, len(template.values))

        return Result(accepted=True, provider_message_id=None)

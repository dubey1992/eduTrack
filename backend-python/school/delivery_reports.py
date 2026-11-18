"""What the phone network says became of a message (docs/dashboard.md, D2).

A provider takes a message ("sent") and later reports whether it reached the
phone. Every school sends through School365ai's own Twilio account
(docs/platform-messaging.md), so one status callback, signed with that
account's auth token, carries every report. The message is found by the id
the provider gave it when it was sent - no school is named in a report, and
none needs to be: the message already belongs to one.
"""

from __future__ import annotations

import logging

from django.utils import timezone

from .enums import MessageChannel, MessageDeliveryStatus
from .models import Message

logger = logging.getLogger(__name__)

# A report never takes a message backwards: reports can arrive out of order,
# and "read" says more than "delivered", which says more than "undelivered".
RANK = {
    None: 0,
    MessageDeliveryStatus.UNDELIVERED: 1,
    MessageDeliveryStatus.DELIVERED: 2,
    MessageDeliveryStatus.READ: 3,
}


def record(provider_message_id: str | None, delivery: str | None, error: str | None = None) -> bool:
    """Writes one report; True when a message changed. An unknown id, or a
    status that is not a delivery, changes nothing."""
    if not provider_message_id or delivery not in RANK or delivery is None:
        return False

    message = (
        Message.objects.filter(
            provider_message_id=provider_message_id,
            channel__in=(MessageChannel.SMS, MessageChannel.WHATSAPP),
        )
        .order_by("id")
        .first()
    )

    if message is None:
        logger.info("A delivery report for an unknown message %s was ignored", provider_message_id)
        return False

    if RANK[delivery] <= RANK.get(message.delivery_status, 0):
        return False

    now = timezone.now()
    changes = {"delivery_status": delivery, "updated_at": now}

    if delivery in MessageDeliveryStatus.reached_the_phone():
        changes["delivered_at"] = message.delivered_at or now
        changes["delivery_error"] = None
    else:
        changes["delivery_error"] = (error or "The phone network could not deliver it.")[:255]

    Message.objects.filter(pk=message.pk).update(**changes)

    return True

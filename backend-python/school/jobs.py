"""The work this backend defers, and what each job does.

Registered by name, so a row queued by one deploy is still readable by the
next - see school/queue.py. Every payload carries ids rather than records: a
job that carried a copy of a payment would act on what was true when it was
queued rather than what is true when it runs, and the gap between those two is
exactly why it was queued.
"""

from __future__ import annotations

import logging

from django.core.mail import EmailMessage
from django.utils import timezone

from . import receipts
from .enums import UserRole, UserStatus
from .models import Payment, User
from .queue import handler

logger = logging.getLogger(__name__)

SEND_PAYMENT_RECEIPT = "payment_receipt"


@handler(SEND_PAYMENT_RECEIPT)
def send_payment_receipt(payment_id: int) -> None:
    """Emails the receipt to the school's admins.

    Queued because rendering a PDF and talking to an SMTP server has no
    business holding up the person recording the payment - and a mail server
    being slow or down must never be the reason a payment fails to save.
    """
    payment = (
        Payment.objects.select_related("school", "created_by").filter(pk=payment_id).first()
    )

    # Deleted between queueing and delivery: nothing to send, and nothing
    # wrong either.
    if payment is None:
        return

    recipients = list(
        User.objects.filter(
            school_id=payment.school_id,
            role=UserRole.SCHOOL_ADMIN,
            status=UserStatus.ACTIVE,
        )
        .exclude(email="")
        .values_list("email", flat=True)
    )

    if not recipients:
        # A school with no active admin is a real situation - newly onboarded,
        # or its only admin deactivated. Worth a line in the log so it can be
        # noticed, but not worth failing the job and retrying forever.
        logger.info(
            "No active School Admin to send a payment receipt to (payment %s, school %s)",
            payment.id,
            payment.school_id,
        )

        return

    message = EmailMessage(
        subject=f"Payment receipt {receipts.receipt_number(payment)}",
        body=(
            f"Please find attached the receipt for the payment recorded against "
            f"{payment.school.name}."
        ),
        to=recipients,
    )
    message.attach(receipts.file_name(payment), receipts.render(payment), "application/pdf")

    # Anything that goes wrong here propagates: the worker retries with a
    # backoff, which is the whole point of the job being queued.
    message.send()

    # Records that the school has been told, and when - what the "Receipt
    # sent" line on the payment screen reads. Written with update() so it
    # cannot collide with an edit made while the mail was going out.
    Payment.objects.filter(pk=payment.id).update(receipt_sent_at=timezone.now())

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

from . import notifications, receipts, sms
from .enums import MessageChannel, MessageStatus, UserRole, UserStatus
from .models import Message, Payment, User
from .queue import handler

logger = logging.getLogger(__name__)

SEND_PAYMENT_RECEIPT = "payment_receipt"


@handler(notifications.SEND_MESSAGE)
def send_message(message_id: int) -> None:
    """Hands one message to its gateway and records what happened.

    The message row is written before this runs and is the thing the school
    reads in its log, so whatever happens here it ends in an honest state:
    sent, failed with a reason, or skipped with a reason. Never left at
    "queued" - a message stuck in queued looks like one still on its way.
    """
    message = Message.objects.select_related("school").filter(pk=message_id).first()

    # Already handled, or handled by a worker that beat this one to it.
    if message is None or message.status != MessageStatus.QUEUED:
        return

    now = timezone.now()

    # The in-app inbox has no gateway - the row *is* the delivery.
    if message.channel == MessageChannel.IN_APP:
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.SENT, sent_at=now, updated_at=now
        )

        return

    if not message.recipient_mobile:
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.SKIPPED,
            failure_reason="No mobile number on record.",
            updated_at=now,
        )

        return

    setting = notifications.settings_for(message.school_id)
    result = sms.gateway(message.provider).send(
        message.recipient_mobile, message.body, setting.sender_id
    )

    if result.accepted:
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.SENT,
            sent_at=now,
            provider_message_id=result.provider_message_id,
            failure_reason=None,
            updated_at=now,
        )
    else:
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.FAILED,
            failure_reason=result.failure_reason,
            updated_at=now,
        )


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


@handler("publish_announcement")
def publish_announcement(announcement_id: int, actor_id: int | None = None) -> None:
    """The fan-out behind a published announcement.

    Nothing to do if the notice has gone, and nothing if it was deleted
    before it went out: somebody took it back, and that is honoured.
    """
    from .models import Announcement
    from .services import AnnouncementService

    announcement = Announcement.objects.select_related("school").filter(pk=announcement_id).first()

    if announcement is None or announcement.deleted_at is not None:
        return

    actor = None if actor_id is None else User.objects.filter(pk=actor_id).first()

    AnnouncementService.fan_out(announcement, actor)


@handler("password_reset_link")
def send_password_reset_link(user_id: int) -> None:
    """Makes a reset token and emails the link.

    Laravel's broker rules: a second link within a minute of the first is not
    sent, and issuing a new token replaces the old one. Only a bcrypt hash of
    the token is stored; the token itself exists in this function and in the
    email, nowhere else - and is never logged.
    """
    import html
    import secrets
    from datetime import timedelta

    from django.conf import settings
    from django.core.mail import EmailMultiAlternatives

    from . import hashing
    from .models import PasswordResetToken

    user = User.objects.filter(pk=user_id).first()

    if user is None:
        return

    now = timezone.now()
    recent = PasswordResetToken.objects.filter(
        email=user.email, created_at__gt=now - timedelta(seconds=settings.PASSWORD_RESET_THROTTLE_SECONDS)
    ).exists()

    if recent:
        return

    token = secrets.token_hex(32)

    PasswordResetToken.objects.filter(email=user.email).delete()
    PasswordResetToken.objects.create(email=user.email, token=hashing.make(token), created_at=now)

    link = f"{settings.FRONTEND_URL.rstrip('/')}/reset-password?token={token}&email={user.email}"
    name = settings.APP_NAME
    expiry = settings.PASSWORD_RESET_EXPIRE_MINUTES

    text = (
        f"{name}\n\n"
        "Hello!\n\n"
        "You are receiving this email because we received a password reset request for your account.\n\n"
        f"Reset Password: {link}\n\n"
        f"This password reset link will expire in {expiry} minutes.\n\n"
        "If you did not request a password reset, no further action is required.\n\n"
        f"Regards,\n{name}\n\n"
        "Smarter Schools. Brighter Futures.\n"
        f"\u00a9 {now.year} {name}. All rights reserved."
    )

    safe_link = html.escape(link)
    body = (
        '<div style="font-family:Arial,sans-serif;color:#1f2937;max-width:570px;margin:0 auto">'
        f'<p style="font-size:19px;font-weight:bold">\U0001f393 {html.escape(name)}</p>'
        "<p>Hello!</p>"
        "<p>You are receiving this email because we received a password reset request for your account.</p>"
        f'<p><a href="{safe_link}" style="background-color:#2563eb;border:8px solid #2563eb;'
        'border-left-width:18px;border-right-width:18px;color:#ffffff;text-decoration:none;'
        'border-radius:4px;display:inline-block">Reset Password</a></p>'
        f"<p>This password reset link will expire in {expiry} minutes.</p>"
        "<p>If you did not request a password reset, no further action is required.</p>"
        f"<p>Regards,<br>{html.escape(name)}</p>"
        '<p style="font-size:12px;color:#6b7280">If you\'re having trouble clicking the "Reset Password" button, '
        f'copy and paste the URL below into your web browser: <a href="{safe_link}" style="color:#2563eb">{safe_link}</a></p>'
        '<p style="font-size:12px;color:#6b7280;text-align:center">Smarter Schools. Brighter Futures.<br>'
        f"\u00a9 {now.year} {html.escape(name)}. All rights reserved.</p>"
        "</div>"
    )

    message = EmailMultiAlternatives(subject="Reset your password", body=text, to=[user.email])
    message.attach_alternative(body, "text/html")
    message.send()

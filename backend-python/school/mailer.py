"""Where email leaves from (docs/communication.md).

Every email the platform sends - a password reset, a payment receipt, a
payslip, the email channel of a message - goes through `connection()`, which
answers one question: the SMTP settings the Super Admin saved in the app, or
the MAIL_* environment when there are none?

The row wins when it exists and is switched on. The environment is what a
fresh deployment sends through before anybody has opened the settings
screen, and what the test suite's in-memory outbox stands in for.
"""

from __future__ import annotations

from django.conf import settings
from django.core.mail import EmailMessage, EmailMultiAlternatives, get_connection
from django.core.mail.backends.smtp import EmailBackend
from django.utils import timezone

from . import crypto
from .models import MailSetting

ENCRYPTIONS = ("none", "tls", "ssl")


def stored() -> MailSetting | None:
    """The saved settings, whether or not they are switched on."""
    return MailSetting.objects.order_by("id").first()


def active() -> MailSetting | None:
    row = stored()

    return row if row is not None and row.is_active else None


def connection(row: MailSetting | None = None):
    """An open-able mail connection for the settings in force."""
    row = active() if row is None else row

    if row is None:
        return get_connection()

    return EmailBackend(
        host=row.host,
        port=row.port,
        username=row.username or None,
        password=crypto.decrypt(row.password) if row.password else None,
        use_tls=row.encryption == "tls",
        use_ssl=row.encryption == "ssl",
        timeout=settings.EMAIL_TIMEOUT,
    )


def sender(row: MailSetting | None = None) -> str:
    row = active() if row is None else row

    if row is None:
        return f"{settings.MAIL_FROM_NAME} <{settings.DEFAULT_FROM_EMAIL}>"

    return f"{row.from_name} <{row.from_address}>"


def message(subject: str, body: str, to: list[str], html: str | None = None, row: MailSetting | None = None):
    """An email addressed and connected, ready to attach to and send."""
    if html is None:
        mail = EmailMessage(subject=subject, body=body, to=to, from_email=sender(row), connection=connection(row))
    else:
        mail = EmailMultiAlternatives(
            subject=subject, body=body, to=to, from_email=sender(row), connection=connection(row)
        )
        mail.attach_alternative(html, "text/html")

    return mail


def send_test(row: MailSetting, to: str) -> None:
    """One email through *these* settings, saved or not, and a note on the
    row of how it went. Raises what the mail server raised, so the screen can
    show the administrator the real reason."""
    now = timezone.now()

    try:
        message(
            subject=f"{settings.APP_NAME} test email",
            body=(
                "This is a test email from "
                f"{settings.APP_NAME}. If you are reading it, the SMTP settings work.\n\n"
                f"Sent {now:%Y-%m-%d %H:%M} UTC."
            ),
            to=[to],
            row=row,
        ).send()
    except Exception as error:
        row.last_tested_at = now
        row.last_test_error = str(error)[:255]

        raise

    row.last_tested_at = now
    row.last_test_error = None

"""The work this backend defers, and what each job does.

Registered by name, so a row queued by one deploy is still readable by the
next - see school/queue.py. Every payload carries ids rather than records: a
job that carried a copy of a payment would act on what was true when it was
queued rather than what is true when it runs, and the gap between those two is
exactly why it was queued.
"""

from __future__ import annotations

import logging

from django.utils import timezone

from . import dates, mailer, notifications, platform_messaging, progress_reports, push, queue, receipts, sms, whatsapp

# Imported for its side effect: registering compute_route_path. The worker
# finds handlers by importing this module, so one that lives elsewhere has
# to be reached from here or the queue grows rows nothing can run.
from . import route_paths  # noqa: F401
from .enums import MessageChannel, MessageStatus, SchoolCategory, UserRole, UserStatus
from .gateways import Result, Template
from .clock import DATE_TIME, SchoolClock
from .models import FeeReceipt, Message, Payment, Student, User
from .queue import handler

logger = logging.getLogger(__name__)

SEND_PAYMENT_RECEIPT = "payment_receipt"
SEND_PROGRESS_REPORT = "progress_report"
SEND_NOTICE = "send_notice"
DEMO_REQUEST_EMAIL = "demo_request_email"
SEND_PUSH = "send_push"
EMAIL_CHANGED_NOTICE = "email_changed_notice"


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

    # The in-app inbox has no gateway - the row *is* the delivery. The phones
    # the person is signed in on are told separately, so a slow Firebase
    # never holds up the inbox (school/push.py).
    if message.channel == MessageChannel.IN_APP:
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.SENT, sent_at=now, updated_at=now
        )

        if message.user_id and push.configured():
            queue.push(SEND_PUSH, {"message_id": message.id})

        return

    # A testing school's texts would go out on School365ai's own account to
    # whatever numbers its made-up records hold (docs/school-categories.md).
    # Email still goes, and so does a demo school's SMS - a prospect is shown
    # the real thing.
    if (
        message.channel in (MessageChannel.SMS, MessageChannel.WHATSAPP)
        and message.school is not None
        and message.school.category == SchoolCategory.TESTING
    ):
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.SKIPPED, failure_reason=notifications.TESTING_SCHOOL, updated_at=now
        )

        return

    address = message.recipient_email if message.channel == MessageChannel.EMAIL else message.recipient_mobile

    if not address:
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.SKIPPED,
            failure_reason=notifications.NO_EMAIL if message.channel == MessageChannel.EMAIL else notifications.NO_MOBILE,
            updated_at=now,
        )

        return

    record_outcome(message, deliver(message), now)


def record_outcome(message: Message, result: Result, now) -> None:
    """However a message was carried, it ends in an honest state: sent, or
    failed with a reason. Never left at "queued", which looks like one still
    on its way."""
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


def deliver(message: Message) -> Result:
    """Hands one external copy to whatever carries its channel. Never raises:
    a provider's bad morning is a failed row with a reason, not a dead worker."""
    # Every school sends through School365ai's own account
    # (docs/platform-messaging.md): the gateway recorded on the message,
    # with the platform's keys.
    if message.channel == MessageChannel.SMS:
        return sms.gateway(message.provider).send(
            message.recipient_mobile, message.body, None, platform_messaging.credentials()
        )

    if message.channel == MessageChannel.WHATSAPP:
        payload = message.template_parameters or {}

        if not payload.get("template"):
            return Result(accepted=False, failure_reason=notifications.NO_WHATSAPP_TEMPLATE)

        return whatsapp.gateway(message.provider).send_template(
            message.recipient_mobile,
            Template(
                name=payload["template"],
                language=payload.get("language") or "en",
                values=payload.get("values") or [],
            ),
            platform_messaging.credentials(),
        )

    if message.channel == MessageChannel.EMAIL:
        subject = message.subject or f"{message.event_label()} - {message.school.name}"

        try:
            mailer.message(subject=subject, body=message.body, to=[message.recipient_email]).send()
        except Exception as error:
            # The reason an administrator reads in the log. SMTP errors name
            # hosts and codes, never the password.
            logger.warning("Email for message %s failed: %s", message.id, error)

            return Result(accepted=False, failure_reason=str(error)[:255] or "The mail server refused the message.")

        return Result(accepted=True)

    return Result(accepted=False, failure_reason=f"No carrier for the {message.channel} channel.")


@handler(SEND_NOTICE)
def send_notice(**payload) -> None:
    """The fan-out behind a notice to a group, written by hand in the
    Communication Center. The payload is the notice itself - there is no row
    for a notice, only the messages it becomes."""
    from .services import NoticeService

    NoticeService.fan_out(payload)


@handler(SEND_PROGRESS_REPORT)
def send_progress_report(message_id: int, student_id: int, academic_term_id: int | None = None) -> None:
    """Emails one child's progress report to their guardian.

    The message row was written before this ran - gated by the school's own
    switches and already in the log - so this only has to render the page,
    carry it, and say honestly what happened.

    Rendered here rather than when the send was asked for: a PDF and an SMTP
    conversation have no business holding up the person who pressed the
    button, and a mail server having a bad morning must never be why the
    request failed.
    """
    # Imported here rather than at the top: performance reaches the report
    # package, which reaches services, which reaches this module.
    from . import performance

    message = Message.objects.select_related("school").filter(pk=message_id).first()

    if message is None or message.status != MessageStatus.QUEUED:
        return

    now = timezone.now()
    student = Student.objects.select_related("school", "class_section__school_class").filter(pk=student_id).first()

    # Removed between the asking and the sending: nothing to send, and
    # nothing wrong either.
    if student is None:
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.SKIPPED,
            failure_reason="The student was removed before the report could be sent.",
            updated_at=now,
        )

        return

    if not message.recipient_email:
        Message.objects.filter(pk=message.pk).update(
            status=MessageStatus.SKIPPED, failure_reason=notifications.NO_EMAIL, updated_at=now
        )

        return

    payload = performance.for_student(student, academic_term_id)
    clock = SchoolClock.for_school(student.school_id)

    try:
        mail = mailer.message(
            subject=message.subject or f"Progress report - {student.name}",
            body=message.body,
            to=[message.recipient_email],
        )
        mail.attach(
            progress_reports.file_name(payload),
            progress_reports.render(
                payload,
                school=student.school,
                generated_at=clock.format(clock.now(), DATE_TIME),
            ),
            "application/pdf",
        )
        mail.send()
    except Exception as error:
        logger.warning("Progress report for message %s failed: %s", message.id, error)
        record_outcome(
            message,
            Result(accepted=False, failure_reason=str(error)[:255] or "The mail server refused the message."),
            now,
        )

        return

    record_outcome(message, Result(accepted=True), now)


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

    message = mailer.message(
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


@handler("announce_results")
def announce_results(assessment_id: int, actor_id: int | None = None) -> None:
    """The fan-out behind a published result (docs/assessments.md).

    Deferred rather than inline: a section of sixty is sixty guardians, and a
    teacher pressing Publish should not wait on a provider - nor should a
    provider being down undo the publishing.
    """
    from .services import AssessmentPublishService

    actor = None if actor_id is None else User.objects.filter(pk=actor_id).first()

    AssessmentPublishService.announce(assessment_id, actor)


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
def send_password_reset_link(user_id: int, welcome: bool = False) -> None:
    """Makes a reset token and emails the link - to somebody who forgot
    their password or, with `welcome`, to a new account that has none yet.

    Laravel's broker rules: a second link within a minute of the first is not
    sent, and issuing a new token replaces the old one. Only a bcrypt hash of
    the token is stored; the token itself exists in this function and in the
    email, nowhere else - and is never logged.
    """
    import html

    from django.conf import settings

    user = User.objects.filter(pk=user_id).first()

    if user is None:
        return

    now = timezone.now()
    link = issue_reset_link(user)

    if link is None:
        return

    name = settings.APP_NAME
    expiry = settings.PASSWORD_RESET_EXPIRE_MINUTES

    if welcome:
        subject = f"Set your password for {name}"
        reason = (
            f"An account has been created for you on {name}. "
            "Choose a password, then sign in with it and this email address."
        )
        action = "Set Password"
        lasts = f"This link will expire in {expiry} minutes."
        otherwise = 'If it has expired, open the sign-in page and use "Forgot password" to be sent a new one.'
    else:
        subject = "Reset your password"
        reason = "You are receiving this email because we received a password reset request for your account."
        action = "Reset Password"
        lasts = f"This password reset link will expire in {expiry} minutes."
        otherwise = "If you did not request a password reset, no further action is required."

    text = (
        f"{name}\n\n"
        "Hello!\n\n"
        f"{reason}\n\n"
        f"{action}: {link}\n\n"
        f"{lasts}\n\n"
        f"{otherwise}\n\n"
        f"Regards,\n{name}\n\n"
        "Smarter Schools. Brighter Futures.\n"
        f"\u00a9 {now.year} {name}. All rights reserved."
    )

    safe_link = html.escape(link)
    body = (
        '<div style="font-family:Arial,sans-serif;color:#1f2937;max-width:570px;margin:0 auto">'
        f'<p style="font-size:19px;font-weight:bold">\U0001f393 {html.escape(name)}</p>'
        "<p>Hello!</p>"
        f"<p>{html.escape(reason)}</p>"
        f'<p><a href="{safe_link}" style="background-color:#2563eb;border:8px solid #2563eb;'
        'border-left-width:18px;border-right-width:18px;color:#ffffff;text-decoration:none;'
        f'border-radius:4px;display:inline-block">{action}</a></p>'
        f"<p>{lasts}</p>"
        f"<p>{html.escape(otherwise)}</p>"
        f"<p>Regards,<br>{html.escape(name)}</p>"
        f'<p style="font-size:12px;color:#6b7280">If you\'re having trouble clicking the "{action}" button, '
        f'copy and paste the URL below into your web browser: <a href="{safe_link}" style="color:#2563eb">{safe_link}</a></p>'
        '<p style="font-size:12px;color:#6b7280;text-align:center">Smarter Schools. Brighter Futures.<br>'
        f"\u00a9 {now.year} {html.escape(name)}. All rights reserved.</p>"
        "</div>"
    )

    mailer.message(subject=subject, body=text, to=[user.email], html=body).send()


def issue_reset_link(user: User) -> str | None:
    """A fresh set-password link for the user, or None when one went out
    less than a minute ago (Laravel's broker rule). Issuing a token replaces
    the old one; only its bcrypt hash is stored, and the token itself is
    never logged."""
    import secrets
    from datetime import timedelta
    from urllib.parse import quote

    from django.conf import settings

    from . import hashing
    from .models import PasswordResetToken

    now = timezone.now()
    recent = PasswordResetToken.objects.filter(
        email=user.email, created_at__gt=now - timedelta(seconds=settings.PASSWORD_RESET_THROTTLE_SECONDS)
    ).exists()

    if recent:
        return None

    token = secrets.token_hex(32)

    PasswordResetToken.objects.filter(email=user.email).delete()
    PasswordResetToken.objects.create(email=user.email, token=hashing.make(token), created_at=now)

    # The web app routes on the URL fragment (Flutter web's default), so the
    # screen lives behind "/#/" - a plain "/reset-password" path reaches the
    # static host instead and is a 404 there.
    # The address is a query value, so it is percent-encoded: a "+" left
    # bare in a query string reads back as a space, and the reset is then
    # refused for an address nobody has.
    return f"{settings.FRONTEND_URL.rstrip('/')}/#/reset-password?token={token}&email={quote(user.email, safe='')}"


@handler("school_admin_welcome")
def send_school_admin_welcome(user_id: int, set_password: bool = False) -> None:
    """A new School Admin's welcome (docs/onboarding.md, O3): their school,
    how to sign in, the first steps. With `set_password`, nobody chose a
    password for them, so the email carries a link to set one."""
    from .models import School
    from .welcome_emails import school_admin

    user = User.objects.filter(pk=user_id).first()
    school = School.objects.filter(pk=getattr(user, "school_id", None)).first()

    if user is None or school is None:
        return

    link = issue_reset_link(user) if set_password else None

    # A link asked for and refused (one went out under a minute ago) would
    # leave a welcome with no way in; the link already sent is the way in.
    if set_password and link is None:
        return

    subject, text, body = school_admin(
        first_name=user.first_name,
        email=user.email,
        school_name=school.name,
        sub_admin=bool(user.is_sub_admin),
        set_password_link=link,
        year=timezone.now().year,
    )
    mailer.message(subject=subject, body=text, to=[user.email], html=body).send()


@handler("school_welcome")
def send_school_welcome(school_id: int, admin_user_id: int | None = None) -> None:
    """A note to the school's own address that its account is set up and
    who its School Admin is (docs/onboarding.md, O3)."""
    from .models import School
    from .welcome_emails import school_note

    school = School.objects.filter(pk=school_id).first()

    if school is None or not school.email:
        return

    admin = User.objects.filter(pk=admin_user_id).first() if admin_user_id else None

    # The admin's own welcome already reached this address.
    if admin is not None and admin.email.lower() == school.email.lower():
        return

    subject, text, body = school_note(
        school_name=school.name,
        admin_name=f"{admin.first_name} {admin.last_name}".strip() if admin else None,
        admin_email=admin.email if admin else None,
        year=timezone.now().year,
    )
    mailer.message(subject=subject, body=text, to=[school.email], html=body).send()


@handler("payslip_email")
def send_payslip(payslip_id: int) -> None:
    """Emails an employee their own payslip, queued when a run is finalized
    or when somebody asks for it to be sent again.

    Only to the employee - pay is personal - and only from a run that is no
    longer a draft, since a draft can still change after it is read.
    """
    from .enums import PayrollRunStatus
    from .models import Payslip
    from .payroll import payslips

    slip = (
        Payslip.objects.select_related("payroll_run", "school", "staff_profile__user").filter(pk=payslip_id).first()
    )

    if slip is None or slip.payroll_run.status == PayrollRunStatus.DRAFT:
        return

    user = slip.staff_profile.user

    from .attendants import is_placeholder_email

    if user.status != UserStatus.ACTIVE or not user.email or is_placeholder_email(user.email):
        logger.info("No active address to send payslip %s to", slip.id)

        return

    message = mailer.message(
        subject=f"Your payslip for {slip.payroll_run.year}-{slip.payroll_run.month:02d} - {slip.school.name}",
        body=f"Hello {user.first_name},\n\nYour payslip is attached.\n\n{slip.school.name}",
        to=[user.email],
    )
    message.attach(payslips.file_name(slip), payslips.render(slip), "application/pdf")
    message.send()

    Payslip.objects.filter(pk=slip.id).update(emailed_at=timezone.now())


@handler("fee_receipt_email")
def send_fee_receipt(receipt_id: int) -> None:
    """Emails a fee receipt's PDF to the student's guardian (docs/fees.md,
    F3), queued when a payment is recorded with "email the guardian" ticked
    or when somebody asks for it from the receipt."""
    from .fees import receipt_pdf
    from .fees.receipts import FeeReceiptService

    receipt = FeeReceiptService.query().filter(pk=receipt_id).first()

    if receipt is None:
        return

    address = receipt.student.guardian_email

    if not address:
        # Removed from the student since it was queued: nothing to send to,
        # and nothing a retry would fix.
        logger.info("No guardian email to send fee receipt %s to", receipt.id)

        return

    message = mailer.message(
        subject=f"Fee receipt {receipt.receipt_number} - {receipt.school.name}",
        body=(
            f"Dear {receipt.student.guardian_name or 'Parent'},\n\n"
            f"Please find attached receipt {receipt.receipt_number} for the fees paid for "
            f"{receipt.student.name}.\n\n{receipt.school.name}"
        ),
        to=[address],
    )
    message.attach(receipt_pdf.file_name(receipt), receipt_pdf.render(receipt), "application/pdf")
    message.send()

    FeeReceipt.objects.filter(pk=receipt.id).update(emailed_at=timezone.now())


@handler(EMAIL_CHANGED_NOTICE)
def send_email_changed_notice(user_id: int, old_email: str) -> None:
    """Tells the old address that the account now signs in somewhere else.

    The whole point is the case where the owner did not do it, so the notice
    says what to do about that - and names the new address only partly, so
    the notice itself does not hand an attacker's address to whoever reads
    the old mailbox, nor the owner's new one to a stranger.
    """
    from django.conf import settings

    user = User.objects.filter(pk=user_id).first()

    if user is None or not old_email:
        return

    local, _, domain = user.email.partition("@")
    masked = (local[:2] + "***@" + domain) if domain else "a new address"
    name = settings.APP_NAME

    mailer.message(
        subject=f"Your {name} sign-in email was changed",
        body=(
            f"Hello {user.first_name},\n\n"
            f"The email address you sign in to {name} with was changed to {masked}.\n\n"
            "If you made this change, there is nothing more to do.\n\n"
            "If you did not, contact your school administrator straight away: they can set your "
            "address back and sign the account out everywhere.\n\n"
            f"{name}"
        ),
        to=[old_email],
    ).send()


@handler(SEND_PUSH)
def send_push(message_id: int) -> None:
    """Buzzes the phones of the person an in-app message was written for."""
    message = Message.objects.filter(pk=message_id).first()

    if message is not None:
        push.deliver(message)


@handler(DEMO_REQUEST_EMAIL)
def send_demo_request_email(demo_request_id: int) -> None:
    """Tells the platform's Super Admins that a school has asked for a demo
    (decided 2026-10-29), with everything the form said, so they can call
    back without opening the app first. Replying goes to the school."""
    from .models import DemoRequest

    request = DemoRequest.objects.filter(pk=demo_request_id).first()
    if request is None:
        return

    recipients = list(
        User.objects.filter(role=UserRole.SUPER_ADMIN, status=UserStatus.ACTIVE)
        .exclude(email__isnull=True)
        .exclude(email="")
        .values_list("email", flat=True)
    )
    if not recipients:
        logger.warning("Demo request %s: no active Super Admin to tell.", request.id)
        return

    when = dates.us(request.preferred_date)
    if request.preferred_time:
        when += f", {request.preferred_time}"
    if request.timezone:
        when += f" ({request.timezone})"

    lines = [
        f"{request.contact_name} from {request.school_name} has asked for a demo.",
        "",
        f"Preferred: {when}",
        f"Email: {request.email}",
        f"Phone: {request.phone}",
        f"Where: {', '.join(part for part in (request.city, request.country) if part)}",
    ]
    if request.expected_students:
        lines.append(f"Students: about {request.expected_students}")
    if request.message:
        lines += ["", "Their message:", request.message]
    lines += ["", "It is in the app under Demo Requests."]

    mail = mailer.message(
        subject=f"Demo request: {request.school_name}", body="\n".join(lines), to=recipients,
    )
    mail.reply_to = [request.email]
    mail.send()

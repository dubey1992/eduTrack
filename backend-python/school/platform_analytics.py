"""Platform analytics, A7 (docs/analytics.md): the whole of School365ai, for
the Super Admin.

Every other analytics view is one school's. This one asks how the platform
is doing: how many schools and people it carries, whether schools are
actually using it, what it is sending, what schools have paid, and who is
asking to join.

- **Now** - schools by status, students and staff on roll, accounts.
- **Month by month** - new schools, sign-ins and the distinct people signing
  in, messages per channel (sent and failed), payments received from schools
  per currency, and early access and demo requests.
- **Each school** - its roll, its last sign-in, and its sign-ins and messages
  over the last 30 days: the quickest way to see a school that has gone
  quiet.
- **Modules** - how many active schools have each switchable module on.

Months are the platform's calendar (PLATFORM_TIMEZONE), since they belong to
no school. Payments are never added across currencies.
"""

from __future__ import annotations

import datetime as dt

from django.db.models import Count, Max, Q, Sum

from . import modules
from .analytics import MONTH, periods
from .clock import DATE, SchoolClock
from .enums import MessageStatus, PaymentStatus, SchoolStatus, StudentStatus, UserStatus
from .models import (
    AuditLog,
    DemoRequest,
    EarlyAccessRequest,
    Message,
    Payment,
    School,
    StaffProfile,
    Student,
    User,
)
from .reports.fees import cash

SIGNED_IN = "user.signed_in"
RECENT_DAYS = 30

# The channels a message leaves the platform by; the inbox is not one.
OUTGOING = ("sms", "whatsapp", "email")

# Payments that brought money in.
RECEIVED = (PaymentStatus.PAID, PaymentStatus.PARTIAL)


def platform(start: dt.date, end: dt.date) -> dict:
    clock = SchoolClock.platform()
    today = clock.now().date()
    months = periods(start, min(end, today), MONTH)
    recent_from = clock.start_of_day_utc(today - dt.timedelta(days=RECENT_DAYS - 1))

    return {
        "as_of": today.isoformat(),
        "totals": _totals(),
        "months": [_month(clock, first, last) for first, last in months],
        "schools": _schools(recent_from),
        "modules": _modules(),
        "recent_days": RECENT_DAYS,
    }


def _totals() -> dict:
    schools = dict(School.objects.order_by().values("status").annotate(n=Count("id")).values_list("status", "n"))

    return {
        "schools_active": schools.get(SchoolStatus.ACTIVE, 0),
        "schools_inactive": schools.get(SchoolStatus.INACTIVE, 0),
        "students": Student.objects.filter(status=StudentStatus.ACTIVE).count(),
        "staff": StaffProfile.objects.filter(user__status=UserStatus.ACTIVE).count(),
        "users": User.objects.filter(status=UserStatus.ACTIVE).count(),
    }


def _month(clock, first: dt.date, last: dt.date) -> dict:
    begins, ends = clock.start_of_day_utc(first), clock.end_of_day_utc(last)
    within = {"created_at__gte": begins, "created_at__lt": ends}

    sign_ins = AuditLog.objects.filter(action=SIGNED_IN, **within)
    messages = (
        Message.objects.filter(channel__in=OUTGOING, status__in=(MessageStatus.SENT, MessageStatus.FAILED), **within)
        .order_by()
        .values("channel", "status")
        .annotate(n=Count("id"))
    )
    by_channel = {channel: {"sent": 0, "failed": 0} for channel in OUTGOING}
    for row in messages:
        by_channel[row["channel"]][row["status"]] = row["n"]

    payments = (
        Payment.objects.filter(status__in=RECEIVED, payment_date__range=(first, last))
        .order_by()
        .values("currency_code")
        .annotate(total=Sum("amount"))
        .order_by("currency_code")
    )

    return {
        "from": first.isoformat(),
        "to": last.isoformat(),
        "new_schools": School.objects.filter(**within).count(),
        "sign_ins": sign_ins.count(),
        "active_users": sign_ins.exclude(user_id=None).values("user_id").distinct().count(),
        "messages": by_channel,
        "payments": [{"currency_code": row["currency_code"], "amount": cash(row["total"])} for row in payments],
        "early_access_requests": EarlyAccessRequest.objects.filter(**within).count(),
        "demo_requests": DemoRequest.objects.filter(**within).count(),
    }


def _schools(recent_from: dt.datetime) -> list[dict]:
    """Every school, busiest first: who is using the product and who has
    gone quiet. Counted in a handful of grouped queries, not one per school."""
    students = dict(
        Student.objects.filter(status=StudentStatus.ACTIVE)
        .order_by().values("school_id").annotate(n=Count("id")).values_list("school_id", "n")
    )
    staff = dict(
        StaffProfile.objects.filter(user__status=UserStatus.ACTIVE)
        .order_by().values("school_id").annotate(n=Count("id")).values_list("school_id", "n")
    )
    sign_ins = {
        row["school_id"]: row
        for row in AuditLog.objects.filter(action=SIGNED_IN)
        .exclude(school_id=None)
        .order_by()
        .values("school_id")
        .annotate(last=Max("created_at"), recent=Count("id", filter=Q(created_at__gte=recent_from)))
    }
    messages = dict(
        Message.objects.filter(channel__in=OUTGOING, status=MessageStatus.SENT, created_at__gte=recent_from)
        .order_by().values("school_id").annotate(n=Count("id")).values_list("school_id", "n")
    )
    clock = SchoolClock.platform()

    rows = []
    for school in School.objects.order_by("name", "id"):
        activity = sign_ins.get(school.id, {})
        rows.append({
            "school_id": school.id,
            "name": school.name,
            "city": school.city,
            "country": school.country,
            "status": school.status,
            "students": students.get(school.id, 0),
            "staff": staff.get(school.id, 0),
            "last_sign_in": activity["last"].isoformat() if activity.get("last") else None,
            "last_sign_in_label": clock.format(activity.get("last"), DATE),
            "recent_sign_ins": activity.get("recent", 0),
            "recent_messages": messages.get(school.id, 0),
        })

    rows.sort(key=lambda row: (row["status"] != SchoolStatus.ACTIVE, -row["recent_sign_ins"], row["name"]))

    return rows


def _modules() -> list[dict]:
    """How many active schools have each switchable module on."""
    active = list(School.objects.filter(status=SchoolStatus.ACTIVE).values_list("id", flat=True))

    return [
        {
            "module": key,
            "label": modules.get(key).label,
            "schools_on": sum(1 for school_id in active if modules.is_enabled(school_id, key)),
            "schools": len(active),
        }
        for key in modules.SWITCHABLE
    ]

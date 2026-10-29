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
  quiet. A list of its own, a page at a time (`school_rows`).
- **Modules** - how many active schools have each switchable module on.

Months are the platform's calendar (PLATFORM_TIMEZONE), since they belong to
no school. Payments are never added across currencies.

Every figure is made of live and trial schools only
(docs/school-categories.md). Demo and testing schools are counted once, as
how many there are, and still appear - labelled - in the per-school list.
"""

from __future__ import annotations

import datetime as dt

from django.db.models import Count, Max, Q, Sum

from . import modules
from .analytics import MONTH, periods
from .clock import DATE, SchoolClock
from .enums import MessageStatus, PaymentStatus, SchoolCategory, SchoolStatus, StudentStatus, UserStatus
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
from .resources import school_category

SIGNED_IN = "user.signed_in"
RECENT_DAYS = 30

# The channels a message leaves the platform by; the inbox is not one.
OUTGOING = ("sms", "whatsapp", "email")

# Payments that brought money in.
RECEIVED = (PaymentStatus.PAID, PaymentStatus.PARTIAL)


COUNTED = {"school__category__in": SchoolCategory.counted()}


def platform(start: dt.date, end: dt.date) -> dict:
    clock = SchoolClock.platform()
    today = clock.now().date()
    months = periods(start, min(end, today), MONTH)

    return {
        "as_of": today.isoformat(),
        "totals": _totals(),
        "months": [_month(clock, first, last) for first, last in months],
        "modules": _modules(),
        "recent_days": RECENT_DAYS,
    }


def _counted_schools():
    return School.objects.filter(category__in=SchoolCategory.counted())


def _totals() -> dict:
    schools = dict(
        _counted_schools().order_by().values("status").annotate(n=Count("id")).values_list("status", "n")
    )

    return {
        "schools_active": schools.get(SchoolStatus.ACTIVE, 0),
        "schools_inactive": schools.get(SchoolStatus.INACTIVE, 0),
        "schools_not_counted": School.objects.exclude(category__in=SchoolCategory.counted()).count(),
        "students": Student.objects.filter(status=StudentStatus.ACTIVE, **COUNTED).count(),
        "staff": StaffProfile.objects.filter(user__status=UserStatus.ACTIVE, **COUNTED).count(),
        "users": User.objects.filter(status=UserStatus.ACTIVE, **COUNTED).count(),
    }


def _month(clock, first: dt.date, last: dt.date) -> dict:
    begins, ends = clock.start_of_day_utc(first), clock.end_of_day_utc(last)
    within = {"created_at__gte": begins, "created_at__lt": ends}

    # A Super Admin's own sign-ins belong to no school, and are not a school
    # using the product.
    sign_ins = AuditLog.objects.filter(action=SIGNED_IN, school__category__in=SchoolCategory.counted(), **within)
    messages = (
        Message.objects.filter(
            channel__in=OUTGOING, status__in=(MessageStatus.SENT, MessageStatus.FAILED), **COUNTED, **within
        )
        .order_by()
        .values("channel", "status")
        .annotate(n=Count("id"))
    )
    by_channel = {channel: {"sent": 0, "failed": 0} for channel in OUTGOING}
    for row in messages:
        by_channel[row["channel"]][row["status"]] = row["n"]

    payments = (
        Payment.objects.filter(status__in=RECEIVED, payment_date__range=(first, last), **COUNTED)
        .order_by()
        .values("currency_code")
        .annotate(total=Sum("amount"))
        .order_by("currency_code")
    )

    return {
        "from": first.isoformat(),
        "to": last.isoformat(),
        "new_schools": _counted_schools().filter(**within).count(),
        "sign_ins": sign_ins.count(),
        "active_users": sign_ins.exclude(user_id=None).values("user_id").distinct().count(),
        "messages": by_channel,
        "payments": [{"currency_code": row["currency_code"], "amount": cash(row["total"])} for row in payments],
        "early_access_requests": EarlyAccessRequest.objects.filter(**within).count(),
        "demo_requests": DemoRequest.objects.filter(**within).count(),
    }


def school_rows(filters: dict) -> list[dict]:
    """Every school matching `filters` (q, category), busiest first: who is
    using the product and who has gone quiet. Counted in a handful of grouped
    queries, not one per school; the caller pages the result.

    Sorted here rather than in SQL because "busiest" is a count from other
    tables - and even at a few thousand schools these are small rows."""
    clock = SchoolClock.platform()
    recent_from = clock.start_of_day_utc(clock.now().date() - dt.timedelta(days=RECENT_DAYS - 1))
    schools = School.objects.order_by("name", "id")

    if filters.get("category"):
        schools = schools.filter(category=filters["category"])

    if filters.get("q"):
        like = f"%{filters['q']}%"
        schools = schools.filter(Q(name__ilike=like) | Q(city__ilike=like))

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
    rows = []
    for school in schools:
        activity = sign_ins.get(school.id, {})
        rows.append({
            "school_id": school.id,
            "name": school.name,
            "city": school.city,
            "country": school.country,
            "status": school.status,
            **school_category(school),
            "students": students.get(school.id, 0),
            "staff": staff.get(school.id, 0),
            "last_sign_in": activity["last"].isoformat() if activity.get("last") else None,
            "last_sign_in_label": clock.format(activity.get("last"), DATE),
            "recent_sign_ins": activity.get("recent", 0),
            "recent_messages": messages.get(school.id, 0),
        })

    # Active customers first, busiest first; demo and testing schools below
    # them, and anything switched off last.
    rows.sort(
        key=lambda row: (
            row["status"] != SchoolStatus.ACTIVE,
            row["category"] not in SchoolCategory.counted(),
            -row["recent_sign_ins"],
            row["name"],
        )
    )

    return rows


def _modules() -> list[dict]:
    """How many active schools have each switchable module on."""
    active = list(_counted_schools().filter(status=SchoolStatus.ACTIVE).values_list("id", flat=True))

    return [
        {
            "module": key,
            "label": modules.get(key).label,
            "schools_on": sum(1 for school_id in active if modules.is_enabled(school_id, key)),
            "schools": len(active),
        }
        for key in modules.SWITCHABLE
    ]

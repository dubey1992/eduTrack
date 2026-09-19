"""Who changed what, and what it was before (CLAUDE.md §13).

One writer for every module. Payroll (Phase 19) was the first to use it;
Phase 21 brought the rest, and sign-in events. A caller says what happened in
its own words - the action, the record, the values before and after - and this
adds who, where and when.

Who and where come from the request being served, without every service
having to be handed it: AuditContextMiddleware notes the request, and the
token authentication notes the user once it has established who is calling.
A caller that knows better - a sign-in, where nobody is authenticated yet -
names the actor itself.

The rules the table depends on:

- **Append-only.** Nothing here updates or deletes a row.
- **Never a secret.** Callers pass the fields that changed, and anything named
  like a password or token is dropped here as well, so one careless caller
  cannot put a credential into a table people read (CLAUDE.md rule 11).
- **Written next to the change, inside its transaction when it has one.** A
  multi-row write (a register, a payroll run, a leave decision) runs in a
  transaction, and its entry is written inside it, so a rolled-back change
  leaves no entry. A single-row edit and its entry are two statements back to
  back. Requests are not atomic as a whole, so each entry goes straight after
  the write it describes, never before.
"""

from __future__ import annotations

import contextvars
import datetime as dt
import re
from decimal import Decimal

from django.utils import timezone

from .models import AuditLog

# Every module that writes to the log - what the audit screen filters by.
MODULES = (
    "academic", "announcements", "attendance", "auth", "communication", "holidays", "leave", "mail", "payments",
    "payroll", "schools", "staff", "staff_attendance", "students", "syllabus", "teaching", "timetable", "transport",
    "users",
)

# Never recorded, whatever a caller passes.
SECRET_KEYS = {
    "password", "password_confirmation", "current_password", "token", "remember_token",
    # Provider accounts and the SMTP password: encrypted in their columns and
    # never in the trail, even as ciphertext.
    "credentials", "auth_token", "access_token",
}

# The request being served and whoever it was authenticated as. Context
# variables rather than thread locals, so each request sees only its own.
_request: contextvars.ContextVar = contextvars.ContextVar("audit_request", default=None)
_actor: contextvars.ContextVar = contextvars.ContextVar("audit_actor", default=None)

# "Use whoever is signed in" - distinct from None, which means "nobody".
CURRENT = object()


class AuditContextMiddleware:
    """Notes the request for the audit writer, and forgets it afterwards."""

    def __init__(self, get_response):
        self.get_response = get_response

    def __call__(self, request):
        request_token = _request.set(request)
        actor_token = _actor.set(None)
        try:
            return self.get_response(request)
        finally:
            _request.reset(request_token)
            _actor.reset(actor_token)


def set_actor(user) -> None:
    """Called by the authentication class once it knows who is calling."""
    _actor.set(user)


def record(
    *,
    actor=CURRENT,
    action: str,
    module: str,
    entity_type: str,
    entity_id: int | None,
    school_id: int | None,
    old: dict | None = None,
    new: dict | None = None,
    request=None,
) -> AuditLog:
    if actor is CURRENT:
        actor = _actor.get()
    if request is None:
        request = _request.get()

    return AuditLog.objects.create(
        school_id=school_id,
        user_id=getattr(actor, "id", None),
        action=action,
        module=module,
        entity_type=entity_type,
        entity_id=entity_id,
        old_values=clean(old),
        new_values=clean(new),
        ip=ip_of(request),
        created_at=timezone.now(),
    )


def clean(values: dict | None):
    """JSON-safe, and without anything secret. Money stays exact as a string."""
    if values is None:
        return None

    def safe(value):
        if isinstance(value, Decimal):
            return str(value)
        if isinstance(value, (dt.date, dt.datetime, dt.time)):
            return value.isoformat()
        if isinstance(value, dict):
            return {key: safe(item) for key, item in value.items() if key not in SECRET_KEYS}
        if isinstance(value, (list, tuple)):
            return [safe(item) for item in value]
        return value

    return safe(values)


def ip_of(request) -> str | None:
    """The address the request came from.

    REMOTE_ADDR, not X-Forwarded-For: a forwarded header is whatever the client
    chose to send, and an audit trail that records a value the actor picked is
    not recording anything.
    """
    if request is None:
        return None

    return (request.META.get("REMOTE_ADDR") or None) if hasattr(request, "META") else None


# -- record changes to a model row (Phase 21) ---------------------------------

# Bookkeeping, not content: every write moves these, and a log that says
# "updated_at changed" on every line hides the lines that matter.
IGNORED_FIELDS = {"created_at", "updated_at", "last_used_at"}


def entity_type(instance) -> str:
    """StaffProfile -> "staff_profile"."""
    return re.sub(r"(?<!^)(?=[A-Z])", "_", type(instance).__name__).lower()


def fields_of(instance) -> dict:
    """A row's own columns, by column name, without bookkeeping or secrets."""
    return {
        field.attname: getattr(instance, field.attname)
        for field in instance._meta.concrete_fields
        if field.attname not in IGNORED_FIELDS and field.attname not in SECRET_KEYS and not field.primary_key
    }


def school_of(instance) -> int | None:
    return getattr(instance, "school_id", None)


def created(module: str, instance, *, action: str | None = None, school_id=None) -> AuditLog:
    return record(
        action=action or f"{entity_type(instance)}.created", module=module, entity_type=entity_type(instance),
        entity_id=instance.pk, school_id=school_id if school_id is not None else school_of(instance),
        new=fields_of(instance),
    )


def updated(module: str, instance, before: dict, *, action: str | None = None, school_id=None) -> AuditLog | None:
    """Records only the columns that actually changed - and nothing at all when
    none did, so saving a form untouched leaves no trace to wade through."""
    after = fields_of(instance)
    changed = [key for key in after if clean({"v": after[key]}) != clean({"v": before.get(key)})]

    if not changed:
        return None

    return record(
        action=action or f"{entity_type(instance)}.updated", module=module, entity_type=entity_type(instance),
        entity_id=instance.pk, school_id=school_id if school_id is not None else school_of(instance),
        old={key: before.get(key) for key in changed}, new={key: after[key] for key in changed},
    )


def deleted(module: str, instance, *, entity_id=None, school_id=None) -> AuditLog:
    """Call before the row goes: afterwards there is nothing left to describe."""
    return record(
        action=f"{entity_type(instance)}.deleted", module=module, entity_type=entity_type(instance),
        entity_id=entity_id if entity_id is not None else instance.pk,
        school_id=school_id if school_id is not None else school_of(instance), old=fields_of(instance),
    )

"""Who changed what, and what it was before (CLAUDE.md §13).

One writer for every module. Payroll (Phase 19) is the first to use it;
Phase 21 brings the rest. A caller says what happened in its own words - the
action, the record, the values before and after - and this adds who, where
and when.

The rules the table depends on:

- **Append-only.** Nothing here updates or deletes a row.
- **Never a secret.** Callers pass the fields that changed, and anything named
  like a password or token is dropped here as well, so one careless caller
  cannot put a credential into a table people read (CLAUDE.md rule 11).
- **Written in the same transaction as the change.** An audit row for a change
  that was rolled back would be a lie, and a change without its row is the gap
  an audit trail exists to close.
"""

from __future__ import annotations

import datetime as dt
from decimal import Decimal

from django.utils import timezone

from .models import AuditLog

# Never recorded, whatever a caller passes.
SECRET_KEYS = {"password", "password_confirmation", "current_password", "token", "remember_token"}


def record(
    *,
    actor,
    action: str,
    module: str,
    entity_type: str,
    entity_id: int | None,
    school_id: int | None,
    old: dict | None = None,
    new: dict | None = None,
    request=None,
) -> AuditLog:
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
        if isinstance(value, (dt.date, dt.datetime)):
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

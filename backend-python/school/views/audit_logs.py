"""The audit log, read-only (Phase 21, docs/security.md).

Administrators read the entries of their own scope; nobody writes here - the
log is written by the services as they change things (school/audit.py). The
same filters answer as JSON for the screen or as a CSV for an auditor.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import csv_export
from ..clock import DATE_TIME, SchoolClock
from ..models import AuditLog
from ..pagination import LaravelPagination
from ..policies import AuditLogPolicy, authorize
from ..requests import AuditLogFilterRequest
from ..resources import timestamp
from ..scope import SchoolScope

# A CSV is for handing to somebody, not for a whole platform's history: past
# this many rows, narrow the filters.
CSV_LIMIT = 10_000


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    authorize(AuditLogPolicy.view_any(request.user))

    form = AuditLogFilterRequest(data=request.query_params.dict(), actor=request.user)
    form.is_valid(raise_exception=True)

    entries = visible_to(request.user, form.validated_data)

    if form.validated_data.get("format") == "csv":
        return csv_export.response(
            "audit-log.csv",
            ["When (UTC)", "School", "User", "Role", "Module", "Action", "Record", "Record ID", "IP", "Before", "After"],
            [csv_line(entry) for entry in entries[:CSV_LIMIT]],
        )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(entries, request)

    clock = SchoolClock.for_user(request.user)

    return paginator.get_paginated_response([audit_log_resource(entry, clock) for entry in page])


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def detail(request, entry_id: int) -> Response:
    authorize(AuditLogPolicy.view_any(request.user))

    # Out of scope reads as not found, the way every tenant record does:
    # nobody learns that an entry exists at a school they cannot see.
    entry = get_object_or_404(visible_to(request.user, {}), pk=entry_id)

    return Response(audit_log_resource(entry, SchoolClock.for_user(request.user)))


def visible_to(actor, filters: dict):
    """Newest first. A platform entry with no school - a Super Admin's own
    sign-in, a failed sign-in for an address nobody has - is the Super
    Admin's alone: a scoped query never matches a null school."""
    entries = SchoolScope.for_actor(actor).apply_to(
        AuditLog.objects.select_related("user", "school"), filters.get("school_id")
    )

    for field in ("user_id", "module", "action", "entity_type", "entity_id"):
        if filters.get(field) is not None:
            entries = entries.filter(**{field: filters[field]})

    # Dates are the reader's own days, not UTC ones.
    clock = SchoolClock.for_user(actor)
    if filters.get("from_date"):
        entries = entries.filter(created_at__gte=clock.start_of_day_utc(filters["from_date"]))
    if filters.get("to_date"):
        entries = entries.filter(created_at__lt=clock.end_of_day_utc(filters["to_date"]))

    return entries.order_by("-created_at", "-id")


def audit_log_resource(entry: AuditLog, clock: SchoolClock | None = None) -> dict:
    """`clock` is the reader's: the label shows the moment on their own wall
    clock, which a client without a timezone database cannot work out."""
    return {
        "id": entry.id,
        "created_at": timestamp(entry.created_at),
        "created_at_label": clock.format(entry.created_at, DATE_TIME) if clock else None,
        "school_id": entry.school_id,
        "school_name": entry.school.name if entry.school_id else None,
        "user_id": entry.user_id,
        "user_name": entry.user.name if entry.user_id else None,
        "user_role": entry.user.role if entry.user_id else None,
        "module": entry.module,
        "action": entry.action,
        "entity_type": entry.entity_type,
        "entity_id": entry.entity_id,
        "old_values": entry.old_values,
        "new_values": entry.new_values,
        "ip": entry.ip,
    }


def csv_line(entry: AuditLog) -> list:
    body = audit_log_resource(entry)

    return [
        body["created_at"], body["school_name"], body["user_name"], body["user_role"], body["module"], body["action"],
        body["entity_type"], body["entity_id"], body["ip"], csv_export.json_cell(body["old_values"]),
        csv_export.json_cell(body["new_values"]),
    ]

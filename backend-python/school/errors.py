"""Every failure this API can return, in the one shape the client can read.

`{code, message, details}` - CLAUDE.md rule 12, and a direct port of
backend/app/Exceptions/ApiExceptionRenderer.php. The Flutter client renders
`message` to the user and reads `details.errors` to mark up a form, so an
error that arrives in a different shape is an error the user never sees
properly. That makes this file contract, not plumbing.

Only the codes M8's endpoints can raise are here. The rest arrive with the
modules that raise them, rather than sitting unreachable in a match arm that
nothing has tested.

Nothing here ever puts a password, a token or an Authorization header into a
message or a log line (CLAUDE.md rule 11), and a genuinely unexpected failure
answers SERVER_ERROR with nothing else - no SQL, no stack trace.
"""

from __future__ import annotations

import logging

from django.http import Http404, JsonResponse
from rest_framework import status
from rest_framework.exceptions import (
    APIException,
    NotAuthenticated,
    NotFound,
    PermissionDenied,
)
from rest_framework.exceptions import ValidationError as DrfValidationError
from rest_framework.response import Response
from rest_framework.views import exception_handler as drf_exception_handler

logger = logging.getLogger(__name__)


class ApiError(APIException):
    """A failure with a code the client is expected to branch on.

    Subclasses name their own status and code, the way the PHP exceptions did:
    the code is part of the contract, so it belongs on the exception rather
    than in a lookup somewhere else that can drift out of step.
    """

    status_code = status.HTTP_409_CONFLICT
    error_code = "HTTP_ERROR"

    def __init__(self, message: str, details: dict | None = None) -> None:
        super().__init__(message)
        self.message = message
        self.details = details or {}


class AccountInactive(ApiError):
    status_code = status.HTTP_403_FORBIDDEN
    error_code = "ACCOUNT_INACTIVE"

    def __init__(self) -> None:
        super().__init__("This account has been deactivated. Contact your school administrator.")


class Unauthenticated(ApiError):
    status_code = status.HTTP_401_UNAUTHORIZED
    error_code = "UNAUTHENTICATED"


class HolidayOverlap(ApiError):
    """Two holidays covering the same day.

    Refused rather than merged: which one a date belongs to decides what the
    calendar says it is, and guessing would put the wrong reason next to a
    closed day.
    """

    status_code = status.HTTP_409_CONFLICT
    error_code = "HOLIDAY_OVERLAP"


class AttendanceAlreadySubmitted(ApiError):
    """A register for this class and day already exists.

    Refused rather than overwritten: a duplicate tap must not silently
    replace a different set of marks. Correcting a day is its own action.
    """

    status_code = status.HTTP_409_CONFLICT
    error_code = "ATTENDANCE_ALREADY_SUBMITTED"


class AttendanceOnHoliday(ApiError):
    status_code = status.HTTP_409_CONFLICT
    error_code = "ATTENDANCE_ON_HOLIDAY"


class NonWorkingDay(ApiError):
    """A weekend. Refused for the same reason a holiday is: every
    working-day figure in the product excludes both, so a Saturday register
    that no percentage counts is worse than none."""

    status_code = status.HTTP_409_CONFLICT
    error_code = "NON_WORKING_DAY"


class HasDependentRecords(ApiError):
    """Something is still built on top of this, so it cannot be removed.

    409 rather than 422: the request was well formed and the record is real -
    the answer is no because of what else exists. The message names what is in
    the way, because "cannot delete" without a reason sends somebody hunting.
    """

    status_code = status.HTTP_409_CONFLICT
    error_code = "HAS_DEPENDENT_RECORDS"


class BulkImportFailed(ApiError):
    """A file that could not be imported, and every reason why.

    422 rather than 409: the upload was a malformed request, and the client
    renders the rows exactly as it renders field errors.
    """

    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "BULK_IMPORT_FAILED"

    def __init__(self, label: str, row_errors: list[dict], row_count: int) -> None:
        self.label = label
        super().__init__(
            "Nothing was imported. Fix the rows below and upload the file again.",
            {"rows": row_errors, "row_count": row_count},
        )


class LeaveOverlap(ApiError):
    """A second live request for days already spoken for.

    Refused rather than merged: a staff member's history should never carry
    two pending or approved requests covering the same day, because the
    attendance sync would then have two answers for what that day was.
    """

    status_code = status.HTTP_409_CONFLICT
    error_code = "LEAVE_OVERLAP"


class LeaveAlreadyReviewed(ApiError):
    """Approve or reject, once. A decision is not re-taken through the same
    endpoint that took it, so a second reviewer's click cannot quietly
    overturn the first's."""

    status_code = status.HTTP_409_CONFLICT
    error_code = "LEAVE_ALREADY_REVIEWED"


class LeaveOnNonWorkingDays(ApiError):
    """A range with no working day in it. There is nothing to take leave
    from: weekends and holidays are already not attendance days."""

    status_code = status.HTTP_409_CONFLICT
    error_code = "LEAVE_ON_NON_WORKING_DAYS"


class StaffProfileRequired(ApiError):
    """The actor has no employment record to apply against.

    409 and a sentence naming the fix, rather than the 403 the shape invites:
    the role is allowed to apply, the data simply is not there yet, and
    "forbidden" would send the user arguing with the wrong person.
    """

    status_code = status.HTTP_409_CONFLICT
    error_code = "STAFF_PROFILE_REQUIRED"


class TeacherScheduleConflict(ApiError):
    """One teacher, two class sections, the same period of the same day.

    The one clash the table's own unique key cannot catch: it guards a class
    section's grid, and this is a collision between two of them.
    """

    status_code = status.HTTP_409_CONFLICT
    error_code = "TEACHER_SCHEDULE_CONFLICT"


class TeachingReportOnHoliday(ApiError):
    """Nothing was taught, so there is nothing to report. Named separately
    from a weekend so the refusal can say which holiday."""

    status_code = status.HTTP_409_CONFLICT
    error_code = "TEACHING_REPORT_ON_HOLIDAY"


class TeachingReportAlreadySubmitted(ApiError):
    """One report per period per day. A second tap must not file a second
    report that the HOD then has to work out which of to believe."""

    status_code = status.HTTP_409_CONFLICT
    error_code = "TEACHING_REPORT_ALREADY_SUBMITTED"


class TeachingReportAlreadyReviewed(ApiError):
    status_code = status.HTTP_409_CONFLICT
    error_code = "TEACHING_REPORT_ALREADY_REVIEWED"


class MessageNotRetryable(ApiError):
    """Only a failed message goes back on the queue. Re-sending anything else
    would either duplicate what was delivered or race the worker already
    holding it."""

    status_code = status.HTTP_409_CONFLICT
    error_code = "MESSAGE_NOT_RETRYABLE"


class UnreachableAudience(ApiError):
    """An announcement that would reach nobody. Refused rather than recorded
    as sent to zero people, which would read as if something went out."""

    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "UNREACHABLE_AUDIENCE"


class UnprocessableRequest(ApiError):
    """Laravel's bare `abort(422)`: no validator involved, so no field
    errors - just the framework's generic sentence under a generic code."""

    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "HTTP_ERROR"

    def __init__(self) -> None:
        super().__init__("An error occurred while processing the request.")


class RouteCapacityFull(ApiError):
    """Every seat on the route's vehicle is spoken for. A student already on
    the route is not counted against it, so moving them between its own stops
    always works."""

    status_code = status.HTTP_409_CONFLICT
    error_code = "ROUTE_CAPACITY_FULL"


def envelope(status_code: int, code: str, message: str, details: dict | None = None) -> Response:
    return Response(
        {
            "code": code,
            "message": message,
            # An empty dict, never an empty list. PHP's [] encodes as a JSON
            # array and the Flutter client cannot parse that as the
            # Map<String, dynamic> it expects; the PHP renderer forces {} for
            # the same reason, once, rather than trusting every branch.
            "details": details or {},
        },
        status=status_code,
    )


def handler(exc, context):
    """DRF's exception hook. Every error the API returns comes through here."""
    if isinstance(exc, ApiError):
        return envelope(exc.status_code, exc.error_code, exc.message, exc.details)

    if isinstance(exc, DrfValidationError):
        return envelope(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "VALIDATION_ERROR",
            "The given data was invalid.",
            {"errors": validation_errors(exc.detail)},
        )

    if isinstance(exc, NotAuthenticated):
        # 401, not DRF's default 403. An API that answers 403 to a missing
        # token tells the client "you are signed in and not allowed", and the
        # client will not send the user to sign in again.
        return envelope(
            status.HTTP_401_UNAUTHORIZED,
            "UNAUTHENTICATED",
            "Authentication is required to access this resource.",
        )

    if isinstance(exc, PermissionDenied):
        return envelope(
            status.HTTP_403_FORBIDDEN,
            "FORBIDDEN",
            "You are not authorized to perform this action.",
        )

    # Both spellings of "not here": Django's, which get_object_or_404 raises,
    # and DRF's, which a view raises directly. They are the same answer to the
    # client and must read the same - the cross-backend diff caught the day
    # they did not, with one of them saying "Not found." under a generic code.
    if isinstance(exc, (Http404, NotFound)):
        return envelope(
            status.HTTP_404_NOT_FOUND,
            "NOT_FOUND",
            "The requested resource was not found.",
        )

    response = drf_exception_handler(exc, context)

    if response is not None:
        if response.status_code == status.HTTP_429_TOO_MANY_REQUESTS:
            return envelope(
                response.status_code,
                "TOO_MANY_REQUESTS",
                "Too many requests. Please try again later.",
            )

        return envelope(response.status_code, "HTTP_ERROR", str(exc))

    # Anything DRF does not recognise is a bug in this backend. It is logged
    # in full so it can be fixed, and described to the client in a sentence
    # that gives away nothing about why.
    logger.exception("Unhandled exception on %s", getattr(context.get("request"), "path", "?"))

    return envelope(
        status.HTTP_500_INTERNAL_SERVER_ERROR,
        "SERVER_ERROR",
        "Something went wrong. Please try again later.",
    )


# -- the failures that never reach a view -----------------------------------
#
# A URL that matches no route, or a crash before DRF is involved, is handled by
# Django itself and never sees the exception hook above. Left alone it answers
# an HTML page, which is how the contract suite found this: a client that asks
# for an endpoint this backend has not ported yet gets a document where it
# expects `{code, message, details}`, and reports a parse error rather than a
# 404.
#
# Laravel answers JSON for anything under api/*, so this does too.


def page_not_found(request, exception=None) -> JsonResponse:
    return JsonResponse(
        {
            "code": "NOT_FOUND",
            "message": "The requested resource was not found.",
            "details": {},
        },
        status=status.HTTP_404_NOT_FOUND,
    )


def server_error(request) -> JsonResponse:
    return JsonResponse(
        {
            "code": "SERVER_ERROR",
            "message": "Something went wrong. Please try again later.",
            "details": {},
        },
        status=status.HTTP_500_INTERNAL_SERVER_ERROR,
    )


def validation_errors(detail) -> dict:
    """DRF's error detail, flattened into Laravel's `{field: [messages]}`.

    Laravel sends every field as a list of strings, whatever the shape of the
    rule that failed, and the client indexes into `errors[field][0]`. DRF
    nests - a dict for a nested serializer, a bare list for a non-field error -
    so the nesting is flattened here rather than at each call site.
    """
    if not isinstance(detail, dict):
        return {"non_field_errors": [str(message) for message in as_list(detail)]}

    flattened = {}

    for field, messages in detail.items():
        flattened[field] = [str(message) for message in as_list(messages)]

    return flattened


def as_list(value) -> list:
    if isinstance(value, list):
        return value

    if isinstance(value, dict):
        # A nested serializer's errors, reported against the parent field.
        # M8 has none of these; flattening rather than dropping them means the
        # first module that does gets a readable message instead of silence.
        return [f"{key}: {' '.join(str(item) for item in as_list(inner))}" for key, inner in value.items()]

    return [value]

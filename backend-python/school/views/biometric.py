"""Fingerprint readers, and who is enrolled on them (docs/biometric.md, B1).

The registry of hardware (B1), and the punches it recorded (B2). Nothing
here touches the staff register - filling check-in and check-out is B3, and
keeping that separate is what lets a school load months of history without
rewriting months of attendance.

Under the staff attendance module rather than one of its own, because a
device is hardware that fills that register's times.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import punches
from ..models import BiometricDevice
from ..errors import envelope
from ..pagination import LaravelPagination
from ..policies import BiometricDevicePolicy, authorize
from ..requests import StoreBiometricDeviceRequest, UpdateBiometricDeviceRequest
from ..resources import biometric_device_resource, biometric_punch_resource
from ..scope import SchoolScope
from ..services import BiometricDeviceService, BiometricPunchService
from .imports import MAX_UPLOAD_BYTES


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    authorize(BiometricDevicePolicy.view_any(request.user))

    found = BiometricDeviceService.visible_to(
        request.user,
        {key: (request.query_params.get(key) or "").strip() for key in ("q", "status", "school_id")},
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([biometric_device_resource(device) for device in page])


def store(request) -> Response:
    form = StoreBiometricDeviceRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    authorize(BiometricDevicePolicy.manage(request.user, form.validated_data["school_id"]))

    created = BiometricDeviceService.create(form.validated_data, request.user)

    return Response(biometric_device_resource(_reload(created.id)), status=status.HTTP_201_CREATED)


@api_view(["GET", "PATCH", "DELETE"])
@permission_classes([IsAuthenticated])
def detail(request, device_id: int) -> Response:
    device = get_object_or_404(BiometricDevice.objects.select_related("school"), pk=device_id)

    # The school check comes before the method, so an id from another school
    # is the same answer whatever somebody meant to do with it.
    authorize(BiometricDevicePolicy.manage(request.user, device.school_id))

    if request.method == "DELETE":
        BiometricDeviceService.delete(device)

        return Response(status=status.HTTP_204_NO_CONTENT)

    if request.method == "PATCH":
        form = UpdateBiometricDeviceRequest(data=request.data, actor=request.user, device=device)
        form.is_valid(raise_exception=True)
        BiometricDeviceService.update(device, form.validated_data)

    return Response(biometric_device_resource(_reload(device.id)))


def _reload(device_id: int) -> BiometricDevice:
    return BiometricDevice.objects.select_related("school").get(pk=device_id)


# -- the punches ------------------------------------------------------------


def _punch_filters(request) -> dict:
    return {
        key: (request.query_params.get(key) or "").strip()
        for key in ("q", "school_id", "date", "from", "to", "unmatched")
    }


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def punch_collection(request) -> Response:
    """What the devices have recorded.

    The count of unattributed punches travels with the page, because "none on
    this page" and "none at all" are different answers and twenty rows cannot
    tell them apart - and the unattributed ones are the only reason somebody
    opens this screen rather than the register.
    """
    authorize(BiometricDevicePolicy.view_any(request.user))

    filters = _punch_filters(request)
    found = BiometricPunchService.visible_to(request.user, filters)

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)
    answer = paginator.get_paginated_response([biometric_punch_resource(punch) for punch in page])
    answer.data["unmatched_total"] = BiometricPunchService.unmatched_count(request.user, filters)

    return answer


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def punch_upload(request) -> Response:
    """A CSV exported from the device software.

    The fallback for a school whose devices cannot reach the internet, and
    the thing that makes this feature work before any device integration
    exists at all (docs/biometric.md).

    **A bad line does not throw away the file.** Unlike the bulk importer,
    whose all-or-nothing rule exists so a half-finished import never has to
    be reconciled, a punch file is history: the rows that are readable are
    worth having, and the ones that are not are listed so somebody can fix
    them and upload again. Re-uploading is safe - a punch already seen lands
    once.
    """
    school_id = SchoolScope.for_actor(request.user).writable_school_id(
        request.data.get("school_id") or None
    )

    authorize(BiometricDevicePolicy.manage(request.user, school_id))

    upload = request.FILES.get("file")

    if upload is None:
        return envelope(
            status.HTTP_422_UNPROCESSABLE_ENTITY,
            "VALIDATION_ERROR",
            "No file was uploaded.",
            {"errors": {"file": ["A file is required."]}},
        )

    # The same ceiling and the same file types as every other import: read
    # whole into memory to be parsed, so the size is checked first.
    if upload.size > MAX_UPLOAD_BYTES or not str(upload.name).lower().endswith((".csv", ".txt")):
        message = (
            "The file field must not be greater than 2048 kilobytes."
            if upload.size > MAX_UPLOAD_BYTES
            else "Upload a CSV file. In Excel, choose File - Save As - CSV."
        )
        return envelope(
            status.HTTP_422_UNPROCESSABLE_ENTITY, "VALIDATION_ERROR", message, {"errors": {"file": [message]}}
        )

    rows, problems = punches.parse_csv(upload)
    outcome = punches.record(school_id, rows)

    answer = outcome.as_dict()
    # The file's own problems and the batch's refusals are one list to the
    # person reading it: both are lines that did not become a punch.
    answer["refused"] = problems + answer["refused"]
    answer["read"] = len(rows)

    return Response(answer)

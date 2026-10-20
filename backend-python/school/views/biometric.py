"""Fingerprint readers, and who is enrolled on them (docs/biometric.md, B1).

A registry and nothing more: no punch is read until B2. What it exists to
settle first is the part that takes the longest in practice - recording what
hardware a school has, and which device id belongs to which member of staff.

Under the staff attendance module rather than one of its own, because a
device is hardware that fills that register's times.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import BiometricDevice
from ..pagination import LaravelPagination
from ..policies import BiometricDevicePolicy, authorize
from ..requests import StoreBiometricDeviceRequest, UpdateBiometricDeviceRequest
from ..resources import biometric_device_resource
from ..services import BiometricDeviceService


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

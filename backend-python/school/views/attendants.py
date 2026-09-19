"""Bus Attendant sign-in and the administrator's side of it (docs/maps.md).

Sign-in (no token yet, throttled like the password form):
- POST auth/attendant/setup - mobile + one-time setup code + a new passcode
  registers this phone; answers with a session token and the device secret.
- POST auth/attendant/login - mobile + passcode + device secret.

For administrators, about one attendant (whoever may edit their staff
record):
- GET    staff/{profile}/attendant - their sign-in: mobile, locked or not,
  whether a setup code is waiting, and their registered devices.
- POST   staff/{profile}/attendant/setup-code - a fresh one-time code,
  shown once.
- DELETE staff/{profile}/attendant/devices/{device} - a lost phone.

Unlocking after five wrong guesses is the existing users/{id}/unlock.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from ..models import AttendantCredential, AttendantDevice, StaffProfile
from ..policies import StaffProfilePolicy, authorize
from ..requests import AttendantLoginRequest, AttendantSetupRequest
from ..resources import attendant_access_resource, timestamp, user_resource
from ..services import AttendantService, StaffProfileService
from ..throttling import AttendantAddressThrottle, AttendantThrottle


def user_agent(request) -> str | None:
    return request.META.get("HTTP_USER_AGENT")


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AttendantThrottle, AttendantAddressThrottle])
def setup(request) -> Response:
    form = AttendantSetupRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data

    user, token, secret = AttendantService.setup(
        data["mobile"], data["setup_code"], data["passcode"], data.get("device_name"), user_agent(request)
    )

    # The device secret is in this answer and nowhere else, ever: the phone
    # keeps it, and only its digest is stored.
    return Response(
        {"token": token, "device_secret": secret, "user": user_resource(user, viewer=user)},
        status=status.HTTP_201_CREATED,
    )


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([AttendantThrottle, AttendantAddressThrottle])
def login(request) -> Response:
    form = AttendantLoginRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data

    user, token = AttendantService.login(data["mobile"], data["passcode"], data["device_secret"], user_agent(request))

    return Response({"token": token, "user": user_resource(user, viewer=user)})


def attendant_profile(request, profile_id: int) -> StaffProfile:
    profile = get_object_or_404(StaffProfile.objects.select_related(*StaffProfileService.WITH), pk=profile_id)

    authorize(StaffProfilePolicy.update(request.user, profile))

    return profile


def access_response(profile) -> Response:
    credential = AttendantService.credential_of(profile)
    credential = AttendantCredential.objects.get(pk=credential.pk)

    return Response(attendant_access_resource(credential, AttendantService.devices_of(profile)))


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def access(request, profile_id: int) -> Response:
    return access_response(attendant_profile(request, profile_id))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def setup_code(request, profile_id: int) -> Response:
    profile = attendant_profile(request, profile_id)

    code, expires = AttendantService.issue_setup_code(profile, request.user)

    return Response(
        {"setup_code": code, "expires_at": timestamp(expires), "login_mobile": AttendantService.credential_of(profile).login_mobile},
        status=status.HTTP_201_CREATED,
    )


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def device(request, profile_id: int, device_id: int) -> Response:
    profile = attendant_profile(request, profile_id)
    AttendantService.credential_of(profile)

    found = get_object_or_404(AttendantDevice, pk=device_id, user_id=profile.user_id)

    AttendantService.revoke_device(profile, found)

    return access_response(profile)

"""The Family app's own API (docs/parent-student-app.md, F0). Everything here
lives under /api/v1/family/, the only part of the API a family account can
reach (school/authentication.py).

Sign-in (no token yet, throttled):
- POST family/auth/setup - mobile + the setup code from the school's letter +
  a new 6-digit passcode registers this phone; answers with a session token
  and the device secret.
- POST family/auth/login - mobile + passcode + that device secret.

Signed in:
- GET  family/me - who they are, their school, and the children they see.
- POST family/auth/logout - ends this session.
"""

from __future__ import annotations

from rest_framework import status
from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import AllowAny, IsAuthenticated
from rest_framework.response import Response

from ..enums import UserRole
from ..errors import NotAFamilyAccount
from ..family_accounts import FamilyAuthService
from ..family_requests import FamilyLoginRequest, FamilySetupRequest
from ..family_resources import family_me_resource
from ..throttling import FamilyAddressThrottle, FamilyThrottle


def user_agent(request) -> str | None:
    return request.META.get("HTTP_USER_AGENT")


def family_user(request):
    """The signed-in family account. A staff session never reaches the
    Family app's data, any more than a family session reaches staff data."""
    if not UserRole.is_family(request.user.role):
        raise NotAFamilyAccount()

    return request.user


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([FamilyThrottle, FamilyAddressThrottle])
def setup(request) -> Response:
    form = FamilySetupRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data

    user, token, secret = FamilyAuthService.setup(
        data["mobile"], data["setup_code"], data["passcode"], data.get("device_name"), user_agent(request)
    )

    # The device secret is in this answer and nowhere else, ever.
    return Response(
        {"token": token, "device_secret": secret, "me": family_me_resource(user, FamilyAuthService.children_of(user))},
        status=status.HTTP_201_CREATED,
    )


@api_view(["POST"])
@permission_classes([AllowAny])
@throttle_classes([FamilyThrottle, FamilyAddressThrottle])
def login(request) -> Response:
    form = FamilyLoginRequest(data=request.data)
    form.is_valid(raise_exception=True)
    data = form.validated_data

    user, token = FamilyAuthService.login(data["mobile"], data["passcode"], data["device_secret"], user_agent(request))

    return Response({"token": token, "me": family_me_resource(user, FamilyAuthService.children_of(user))})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def me(request) -> Response:
    user = family_user(request)

    return Response(family_me_resource(user, FamilyAuthService.children_of(user)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout(request) -> Response:
    family_user(request)
    request.auth.delete()

    return Response(status=status.HTTP_204_NO_CONTENT)

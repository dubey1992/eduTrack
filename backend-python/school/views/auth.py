"""Signing in, signing out, and the session the client holds.

Port of AuthController. Thin on purpose: validate, call the service, render
(CLAUDE.md rule 8).

Nothing in this module logs a request body, and nothing returns a password
hash - the session user resource has no `password` key at all, so it cannot
leak by somebody adding a field later (CLAUDE.md rule 11).
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..requests import ChangePasswordRequest, LoginRequest
from ..resources import user_resource
from ..services import AuthService
from ..throttling import LoginAddressThrottle, LoginThrottle


@api_view(["POST"])
@permission_classes([])
@throttle_classes([LoginThrottle, LoginAddressThrottle])
def login(request) -> Response:
    form = LoginRequest(data=request.data)
    form.is_valid(raise_exception=True)

    user, token = AuthService.login(
        form.validated_data["email"],
        form.validated_data["password"],
    )

    return Response({"user": user_resource(user, viewer=user), "token": token})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def me(request) -> Response:
    return Response(user_resource(request.user, viewer=request.user))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def change_password(request) -> Response:
    form = ChangePasswordRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    AuthService.change_password(
        request.user,
        form.validated_data["password"],
        current_token=request.auth,
    )

    return Response({"message": "Password changed successfully."})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def logout(request) -> Response:
    AuthService.logout(request.auth)

    return Response({"message": "Logged out successfully."})

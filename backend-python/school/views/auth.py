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

from ..requests import ChangePasswordRequest, ForgotPasswordRequest, LoginRequest, ResetPasswordRequest
from ..resources import user_resource
from ..errors import envelope
from ..services import AuthService, PasswordResetService
from ..throttling import (
    LoginAddressThrottle,
    LoginThrottle,
    PasswordResetAddressThrottle,
    PasswordResetThrottle,
)


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


@api_view(["POST"])
@permission_classes([])
@throttle_classes([PasswordResetThrottle, PasswordResetAddressThrottle])
def forgot_password(request) -> Response:
    form = ForgotPasswordRequest(data=request.data)
    form.is_valid(raise_exception=True)

    PasswordResetService.request_link(form.validated_data["email"])

    # The same answer whether or not the address has an account.
    return Response({"message": "If an account exists for that email, a password reset link has been sent."})


@api_view(["POST"])
@permission_classes([])
@throttle_classes([PasswordResetThrottle, PasswordResetAddressThrottle])
def reset_password(request) -> Response:
    form = ResetPasswordRequest(data=request.data)
    form.is_valid(raise_exception=True)

    reset = PasswordResetService.reset(
        form.validated_data["email"], form.validated_data["token"], form.validated_data["password"]
    )

    # One answer for a wrong token, an expired one and an address with no
    # account - telling them apart would say which addresses exist.
    if not reset:
        return envelope(422, "INVALID_RESET_TOKEN", "This password reset link is invalid or has expired.")

    return Response({"message": "Password reset successfully."})


"""Signing in, signing out, and the session the client holds.

Port of AuthController. Thin on purpose: validate, call the service, render
(CLAUDE.md rule 8).

Nothing in this module logs a request body, and nothing returns a password
hash - the session user resource has no `password` key at all, so it cannot
leak by somebody adding a field later (CLAUDE.md rule 11).
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes, throttle_classes
from rest_framework.exceptions import NotFound
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..requests import ChangePasswordRequest, ForgotPasswordRequest, LoginRequest, ResetPasswordRequest
from ..resources import timestamp, user_resource
from ..errors import envelope
from .. import tokens
from ..clock import DATE_TIME, SchoolClock
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
        device=request.META.get("HTTP_USER_AGENT"),
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
    AuthService.logout(request.user, request.auth)

    return Response({"message": "Logged out successfully."})


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def sessions(request) -> Response:
    """Where this person is signed in (Phase 21), most recently used first."""
    clock = SchoolClock.for_user(request.user)

    return Response({"data": [session_resource(row, request.auth, clock) for row in tokens.sessions_of(request.user)]})


@api_view(["DELETE"])
@permission_classes([IsAuthenticated])
def end_session(request, session_id: int) -> Response:
    # Another person's session, or one already gone, is simply not found:
    # nobody learns whether an id exists.
    if not AuthService.end_session(request.user, session_id):
        raise NotFound()

    return Response({"message": "Signed out of that device."})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def end_other_sessions(request) -> Response:
    ended = AuthService.end_other_sessions(request.user, request.auth)

    return Response({"message": "Signed out of all other devices.", "ended": ended})


def session_resource(row, current, clock) -> dict:
    # Labels on the holder's own clock, which the client cannot compute.
    return {
        "id": row.id,
        "device": row.name,
        "signed_in_at": timestamp(row.created_at),
        "signed_in_label": clock.format(row.created_at, DATE_TIME),
        "last_used_at": timestamp(row.last_used_at),
        "last_used_label": clock.format(row.last_used_at, DATE_TIME),
        "current": current is not None and row.pk == current.pk,
    }


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


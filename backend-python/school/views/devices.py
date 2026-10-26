"""The phones a person is signed in on, for push (docs/teacher-app.md, T6).

The app registers its Firebase token after signing in and every time Firebase
hands it a new one, and forgets it on the way out. Both act only on the
caller: there is no way to register a phone for somebody else, or to remove
somebody else's.
"""

from __future__ import annotations

from django.utils import timezone
from rest_framework import serializers, status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import DeviceToken

PLATFORMS = ("android", "ios", "web")
APPS = ("staff", "driver")


class RegisterDeviceRequest(serializers.Serializer):
    token = serializers.CharField(max_length=255)
    platform = serializers.ChoiceField(choices=PLATFORMS)
    app = serializers.ChoiceField(choices=APPS)


class ForgetDeviceRequest(serializers.Serializer):
    token = serializers.CharField(max_length=255)


@api_view(["POST", "DELETE"])
@permission_classes([IsAuthenticated])
def devices(request) -> Response:
    if request.method == "DELETE":
        form = ForgetDeviceRequest(data=request.data)
        form.is_valid(raise_exception=True)

        # Only the caller's own; anybody else's token is left alone, and
        # saying so would tell them it exists.
        DeviceToken.objects.filter(user_id=request.user.id, token=form.validated_data["token"]).delete()

        return Response(status=status.HTTP_204_NO_CONTENT)

    form = RegisterDeviceRequest(data=request.data)
    form.is_valid(raise_exception=True)
    now = timezone.now()

    # One row per install of the app. A phone that somebody else signed in
    # on before moves to the caller, so it never shows them the other
    # person's news.
    DeviceToken.objects.update_or_create(
        token=form.validated_data["token"],
        defaults={
            "user_id": request.user.id,
            "platform": form.validated_data["platform"],
            "app": form.validated_data["app"],
            "last_seen_at": now,
            "updated_at": now,
        },
        create_defaults={
            "user_id": request.user.id,
            "platform": form.validated_data["platform"],
            "app": form.validated_data["app"],
            "last_seen_at": now,
            "created_at": now,
            "updated_at": now,
        },
    )

    return Response({"registered": True})

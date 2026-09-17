"""A user's own in-app messages.

Port of InboxController. There is no policy here, on purpose: every query is
pinned to the signed-in user, so there is nothing to authorize beyond being
signed in - except marking one message read, where the message is named by
id and has to be the reader's own.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.exceptions import PermissionDenied
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..models import Message
from ..pagination import LaravelPagination
from ..resources import message_resource
from ..services import MessageService


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def messages(request) -> Response:
    found = MessageService.inbox(request.user, request.query_params.get("unread"))

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(found, request)

    return paginator.get_paginated_response([message_resource(row) for row in page])


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def unread_count(request) -> Response:
    return Response({"unread": MessageService.unread_count(request.user)})


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def read(request, message_id: int) -> Response:
    found = get_object_or_404(Message, pk=message_id)

    # The reader's own, whichever channel - the check is ownership, not
    # whether the message would appear in the feed.
    if found.user_id != request.user.id:
        raise PermissionDenied()

    return Response(message_resource(MessageService.mark_read(found)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def read_all(request) -> Response:
    return Response({"marked": MessageService.mark_all_read(request.user)})

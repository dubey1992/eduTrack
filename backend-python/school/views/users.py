"""Admin accounts.

Port of UserController. The only accounts this endpoint creates are admin-tier
ones - a Super Admin onboards a School Admin or a Group Admin, and an admin
onboards a Sub Admin for their own school. Teachers and other staff go through
Teachers & Staff instead, which creates the login and the employment record
together; one created here would have no StaffProfile and be invisible to
Attendance and Leave.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework import status
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..enums import UserStatus
from ..models import User
from ..pagination import LaravelPagination
from ..policies import UserPolicy, authorize
from ..requests import StoreUserRequest, UpdateUserRequest
from ..resources import user_resource
from ..services import AuthService, UserService


@api_view(["GET", "POST"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    if request.method == "POST":
        return store(request)

    return index(request)


def index(request) -> Response:
    authorize(UserPolicy.view_any(request.user))

    users = UserService.visible_to(
        request.user,
        {
            "role": request.query_params.get("role"),
            "roles": request.query_params.get("roles"),
            "status": request.query_params.get("status"),
            "school_id": request.query_params.get("school_id"),
        },
    )

    paginator = LaravelPagination()
    page = paginator.paginate_queryset(users, request)

    return paginator.get_paginated_response(
        [user_resource(user, viewer=request.user) for user in page]
    )


def store(request) -> Response:
    authorize(UserPolicy.create(request.user))

    form = StoreUserRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    user = UserService.create(request.user, form.validated_data)

    return Response(
        user_resource(reload(user.id), viewer=request.user),
        status=status.HTTP_201_CREATED,
    )


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request, user_id: int) -> Response:
    user = get_object_or_404(User.objects.select_related("school"), pk=user_id)

    if request.method == "PATCH":
        return update(request, user)

    authorize(UserPolicy.view(request.user, user))

    return Response(user_resource(user, viewer=request.user))


def update(request, user: User) -> Response:
    authorize(UserPolicy.update(request.user, user))

    form = UpdateUserRequest(data=request.data, actor=request.user, user=user)
    form.is_valid(raise_exception=True)

    UserService.update(user, form.validated_data)

    return Response(user_resource(reload(user.id), viewer=request.user))


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def activate(request, user_id: int) -> Response:
    return set_status(request, user_id, UserStatus.ACTIVE)


@api_view(["PATCH"])
@permission_classes([IsAuthenticated])
def deactivate(request, user_id: int) -> Response:
    return set_status(request, user_id, UserStatus.INACTIVE)


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def unlock(request, user_id: int) -> Response:
    """Lets a locked-out user sign in again straight away (Phase 21).

    Whoever may switch the account on and off may unlock it - the same
    decision about the same person.
    """
    user = get_object_or_404(User.objects.select_related("school"), pk=user_id)

    authorize(UserPolicy.set_status(request.user, user))

    AuthService.unlock(user)

    return Response(user_resource(reload(user.id), viewer=request.user))


def set_status(request, user_id: int, status_value: str) -> Response:
    user = get_object_or_404(User.objects.select_related("school"), pk=user_id)

    authorize(UserPolicy.set_status(request.user, user))

    if status_value == UserStatus.ACTIVE:
        UserService.activate(user)
    else:
        UserService.deactivate(user)

    return Response(user_resource(reload(user.id), viewer=request.user))


def reload(user_id: int) -> User:
    return User.objects.select_related("school").get(pk=user_id)

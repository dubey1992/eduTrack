"""The roles and permissions matrix (docs/settings.md).

Read by every administrator, so a School Admin can see what their staff may
do; edited by the Super Admin only. Saving takes the whole matrix and keeps
only the cells that differ from the defaults, so "reset" is simply deleting
every row.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..policies import RolePermissionPolicy, authorize
from ..requests import UpdatePermissionsRequest
from ..resources import permissions_resource
from ..services import RolePermissionService


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def matrix(request) -> Response:
    if request.method == "GET":
        authorize(RolePermissionPolicy.view(request.user))

        return Response(permissions_resource(request.user))

    authorize(RolePermissionPolicy.update(request.user))

    form = UpdatePermissionsRequest(data=request.data)
    form.is_valid(raise_exception=True)

    RolePermissionService.save(form.validated_data["matrix"], request.user)

    return Response(permissions_resource(request.user))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def reset(request) -> Response:
    authorize(RolePermissionPolicy.update(request.user))

    RolePermissionService.reset(request.user)

    return Response(permissions_resource(request.user))

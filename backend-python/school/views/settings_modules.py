"""Module settings (docs/settings.md).

Which modules a school has on, and each module's own settings. A Super Admin
reads and edits any school's, naming it with `school_id`; a School Admin
their own. Only a Super Admin moves the platform switch; the school switch
and the settings belong to both.
"""

from __future__ import annotations

from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import modules
from ..enums import UserRole
from ..errors import UnprocessableRequest
from ..models import School
from ..policies import ModuleSettingPolicy, authorize
from ..requests import UpdateModuleSettingRequest, php_int
from ..resources import module_setting_resource
from ..services import ModuleSettingService


def school_for(request) -> int:
    """The school being configured: named by a Super Admin, the actor's own
    otherwise. A Super Admin who names none is refused with a 422 rather
    than shown school zero - there is nothing to configure there."""
    raw = request.query_params.get("school_id", request.data.get("school_id") if request.method != "GET" else None)
    requested = None if raw in (None, "") else php_int(raw)

    if request.user.role == UserRole.SUPER_ADMIN:
        if requested is None:
            raise UnprocessableRequest()

        return requested

    return requested if requested is not None else request.user.school_id


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def collection(request) -> Response:
    school_id = school_for(request)

    authorize(ModuleSettingPolicy.view(request.user, school_id))

    school = get_object_or_404(School, pk=school_id)
    rows = modules.rows_for(school.id)

    return Response(
        [module_setting_resource(module, rows.get(module.key), request.user) for module in modules.MODULES]
    )


@api_view(["PUT"])
@permission_classes([IsAuthenticated])
def detail(request, module: str) -> Response:
    if module not in modules.BY_KEY:
        return Response({"code": "NOT_FOUND", "message": "No such module.", "details": {}}, status=404)

    school_id = school_for(request)

    authorize(ModuleSettingPolicy.update(request.user, school_id))

    form = UpdateModuleSettingRequest(data=request.data, module=modules.get(module), actor=request.user)
    form.is_valid(raise_exception=True)

    school = get_object_or_404(School, pk=school_id)
    row = ModuleSettingService.update(school.id, module, form.validated_data, request.user)

    return Response(module_setting_resource(modules.get(module), row, request.user))

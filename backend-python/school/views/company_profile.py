"""School365ai's own business details - Super Admin only
(docs/pdf-design.md, phase 5).

Read and saved from the Company details screen; printed as the issuer on the
receipt a school gets for paying the platform (school/receipts.py).
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from ..policies import CompanyProfilePolicy, authorize
from ..requests import UpdateCompanyProfileRequest
from ..resources import company_profile_resource
from ..services import CompanyProfileService


@api_view(["GET", "PUT"])
@permission_classes([IsAuthenticated])
def profile(request) -> Response:
    authorize(CompanyProfilePolicy.manage(request.user))

    if request.method == "GET":
        return Response(company_profile_resource(CompanyProfileService.current()))

    form = UpdateCompanyProfileRequest(data=request.data)
    form.is_valid(raise_exception=True)

    return Response(company_profile_resource(CompanyProfileService.save(form.validated_data, request.user)))

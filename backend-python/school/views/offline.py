"""The web app's offline copy (docs/offline-web.md, O2).

- GET offline/snapshot - what a trusted computer keeps: the students, classes,
  staff and fee dues this person may already see, in one answer.
"""

from __future__ import annotations

from rest_framework.decorators import api_view, permission_classes
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import offline_snapshot
from ..policies import authorize


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def snapshot(request) -> Response:
    actor = request.user
    authorize(actor.role in offline_snapshot.OFFICE_ROLES and actor.school_id is not None)

    return Response(offline_snapshot.build(actor))

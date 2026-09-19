"""My Profile (docs/profile.md): a person's own details, email and photo.

**No id in any of these paths.** Every profile endpoint acts on the account
the token belongs to, so there is nothing in a request to change that would
reach somebody else's profile. An administrator changing another person's
details keeps using Users or Teachers & Staff, as before.

The one endpoint that names a person, the photo, is a read: the owner, or an
administrator whose scope covers them. Anyone else gets a 404, the same as a
person with no photo, so the answer never says whether a photo exists.
"""

from __future__ import annotations

from django.http import Http404, HttpResponse
from django.shortcuts import get_object_or_404
from rest_framework.decorators import api_view, parser_classes, permission_classes
from rest_framework.exceptions import ValidationError
from rest_framework.parsers import FormParser, JSONParser, MultiPartParser
from rest_framework.permissions import IsAuthenticated
from rest_framework.response import Response

from .. import photos
from ..enums import UserRole
from ..errors import KeptBySchoolOffice
from ..models import User
from ..policies import administers, in_scope
from ..requests import ChangeEmailRequest, UpdateProfileRequest
from ..resources import profile_resource
from ..services import ProfileService


def own(request) -> User:
    """The signed-in account, with what the profile shows loaded."""
    return User.objects.select_related("school", "staffprofile__department").get(pk=request.user.pk)


@api_view(["GET", "PATCH"])
@permission_classes([IsAuthenticated])
def detail(request) -> Response:
    if request.method == "GET":
        return Response(profile_resource(own(request)))

    form = UpdateProfileRequest(data=request.data)
    form.is_valid(raise_exception=True)

    ProfileService.update(own(request), form.validated_data)

    return Response(profile_resource(own(request)))


@api_view(["POST"])
@permission_classes([IsAuthenticated])
def email(request) -> Response:
    # An attendant has no password to confirm this with, and does not sign
    # in with an email: their school office keeps their address.
    if request.user.role == UserRole.BUS_ATTENDANT:
        raise KeptBySchoolOffice("Your school office keeps your email address. Ask them to change it.")

    form = ChangeEmailRequest(data=request.data, actor=request.user)
    form.is_valid(raise_exception=True)

    ProfileService.change_email(request.user, form.validated_data["email"], current_token=request.auth)

    return Response(profile_resource(own(request)))


@api_view(["POST", "DELETE"])
@permission_classes([IsAuthenticated])
@parser_classes([MultiPartParser, FormParser, JSONParser])
def photo(request) -> Response:
    if request.method == "DELETE":
        ProfileService.remove_photo(own(request))

        return Response(profile_resource(own(request)))

    try:
        data, extension = photos.prepare(request.FILES.get("photo"))
    except photos.PhotoRejected as rejected:
        # Shaped like any other field error, so the app shows it under the
        # photo the way it shows a bad mobile number under the mobile field.
        raise ValidationError({"photo": [str(rejected)]})

    ProfileService.set_photo(own(request), data, extension)

    return Response(profile_resource(own(request)))


def may_see_photo(actor: User, person: User) -> bool:
    """The owner; a Super Admin; an administrator whose scope covers the
    person's school. A person with no school (a Super Admin) is in nobody's
    scope, so only they and other Super Admins see their photo."""
    if person.id == actor.id or actor.role == UserRole.SUPER_ADMIN:
        return True

    return person.school_id is not None and administers(actor) and in_scope(actor, person.school_id)


@api_view(["GET"])
@permission_classes([IsAuthenticated])
def user_photo(request, user_id: int):
    actor = request.user
    person = get_object_or_404(User, pk=user_id)

    if not may_see_photo(actor, person):
        raise Http404

    stored = photos.read(person.photo_path)

    if stored is None:
        raise Http404

    data, content_type = stored
    response = HttpResponse(data, content_type=content_type)
    # Private: a shared cache must never hand one person's photo to another.
    # The URL changes with every new photo, so the browser may keep it.
    response["Cache-Control"] = "private, max-age=86400"

    return response


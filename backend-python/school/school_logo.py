"""A school's logo (docs/school-logo.md, decided 2026-11-17).

The School Admin uploads it; a Super Admin may too, for any school. It is
checked and re-encoded exactly like a profile photo (school/photos.py), only
kept larger, and stored under `school-logos/`. It shows at the top of the
menu for everyone at the school and is printed on the school's PDFs.

**A school's profile is complete once it has a logo.** Until then the app
asks its School Admin for one at every sign-in.

**Read only by people at the school.** The logo is not secret, but nothing in
this app is served to strangers by id: anyone outside the school's scope gets
the same 404 as a school with no logo.
"""

from __future__ import annotations

from django.db import transaction
from django.utils import timezone

from . import audit, photos
from .enums import UserRole
from .models import School, User
from .policies import in_scope

FOLDER = "school-logos"

# Big enough to stay sharp in a PDF's band and on a retina menu; small enough
# that every page of the app can fetch it without thinking.
MAX_SIDE = 800


def may_change(actor: User, school: School) -> bool:
    """A Super Admin, or an administrator of this school (or of its group)."""
    if actor.role == UserRole.SUPER_ADMIN:
        return True

    return UserRole.administers_school(actor.role) and in_scope(actor, school.id)


def may_see(actor: User, school: School) -> bool:
    """Anyone whose school this is, its group's admins, and Super Admins."""
    return in_scope(actor, school.id)


def url_of(school: School | None) -> str | None:
    """Where the app fetches the logo, or None when there is none. The file
    name is in the address, so a new logo is a new address and nothing cached
    for the old one is shown."""
    if school is None or not school.logo_path:
        return None

    version = school.logo_path.rsplit("/", 1)[-1].split(".", 1)[0][:12]

    return f"/schools/{school.id}/logo?v={version}"


def profile_complete(school: School | None) -> bool:
    """Whether the school's profile has everything it needs - today, a logo.
    An account with no school (a Super Admin) has nothing to complete."""
    return school is None or bool(school.logo_path)


def prepare(upload) -> tuple[bytes, str]:
    """The upload, checked and re-encoded. Raises photos.PhotoRejected."""
    return photos.prepare(upload, max_side=MAX_SIDE, noun="logo")


def set_logo(school: School, data: bytes, extension: str) -> School:
    """Stores the new logo, points the school at it, and only then removes
    the old file - a failure part-way never leaves the school pointing at
    nothing."""
    old = school.logo_path
    path = photos.store(data, extension, folder=FOLDER)

    try:
        with transaction.atomic():
            School.objects.filter(pk=school.pk).update(logo_path=path, updated_at=timezone.now())
            audit.record(
                action="school.logo_changed", module="schools", entity_type="school", entity_id=school.id,
                school_id=school.id, old={"had_logo": old is not None}, new={"has_logo": True},
            )
    except Exception:
        photos.remove(path)
        raise

    photos.remove(old)

    return School.objects.get(pk=school.pk)


def remove_logo(school: School) -> School:
    old = school.logo_path

    with transaction.atomic():
        School.objects.filter(pk=school.pk).update(logo_path=None, updated_at=timezone.now())
        audit.record(
            action="school.logo_removed", module="schools", entity_type="school", entity_id=school.id,
            school_id=school.id, old={"had_logo": old is not None}, new={"has_logo": False},
        )

    photos.remove(old)

    return School.objects.get(pk=school.pk)


def read(school: School) -> tuple[bytes, str] | None:
    """The stored logo's bytes and content type, or None."""
    return photos.read(school.logo_path) if school.logo_path else None

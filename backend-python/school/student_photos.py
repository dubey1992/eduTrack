"""A student's photo (docs/student-photos.md, P1).

The checking and storing are the profile photo's (school/photos.py): the
upload is decoded and re-encoded, never trusted. A student's photo differs
in two ways: it is cut to a 3:4 passport shape around its centre (D2), the
shape of the box printed on admit cards and report cards, and it is kept a
little larger - 600 pixels on the longer side - so it prints sharp.

Only the current photo is kept. A new one replaces the file, and removing
one deletes it. Every change goes in the audit log, which records that the
photo changed and never the image.
"""

from __future__ import annotations

from django.db import transaction
from django.utils import timezone

from . import audit, photos
from .models import Student

FOLDER = "student-photos"
MAX_SIDE = 600
ASPECT = (3, 4)


def prepare(upload) -> tuple[bytes, str]:
    """The upload as a stored student photo will be: (bytes, extension).
    Raises photos.PhotoRejected with a sentence the person can act on."""
    return photos.prepare(upload, max_side=MAX_SIDE, aspect=ASPECT)


def set_photo(student: Student, data: bytes, extension: str, *, request=None) -> None:
    """Stores the new photo, points the student at it, and only then removes
    the old file - so a failure part-way never leaves the student pointing
    at nothing."""
    old = student.photo_path
    path = photos.store(data, extension, folder=FOLDER)

    try:
        with transaction.atomic():
            Student.objects.filter(pk=student.pk).update(photo_path=path, updated_at=timezone.now())
            audit.record(
                action="student.photo_changed", module="students", entity_type="student",
                entity_id=student.id, school_id=student.school_id,
                new={"had_photo": old is not None}, request=request,
            )
    except Exception:
        photos.remove(path)
        raise

    photos.remove(old)


def remove_photo(student: Student, *, request=None) -> None:
    old = student.photo_path

    if old is None:
        return

    with transaction.atomic():
        Student.objects.filter(pk=student.pk).update(photo_path=None, updated_at=timezone.now())
        audit.record(
            action="student.photo_removed", module="students", entity_type="student",
            entity_id=student.id, school_id=student.school_id, request=request,
        )

    photos.remove(old)


def photo_url(student: Student) -> str | None:
    """Where the app fetches the photo, or None for initials. Relative to
    the API's base, carrying part of the stored file's random name, so a new
    photo is a new address and a cached old one is never shown for it."""
    if not student.photo_path:
        return None

    version = student.photo_path.rsplit("/", 1)[-1].split(".", 1)[0][:12]

    return f"/students/{student.id}/photo?v={version}"

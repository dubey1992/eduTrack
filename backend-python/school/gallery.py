"""Events and photos for the Family app (docs/mobile-apps-review.md, M12, 8.6,
decided by the owner 2026-11-25).

- The school's admins post an event for the whole school or for one class;
  a class teacher posts to their own class only.
- An event has a title, a date, an optional description and up to 20
  photos, each decoded and re-encoded to at most 1600 px (school/photos.py),
  so nothing that rode along in the camera file is kept. A 400 px copy is
  kept beside it for the grid, so a parent scrolling on a phone's data does
  not download full pictures.
- Whoever posted it, or an admin, changes and deletes it and adds photos;
  an admin can remove any photo.
- Parents see the school's events and those of their children's classes,
  once an event has a photo. Every file is read through a signed-in
  endpoint - never a public address.

Children are not tagged in photos: that waits for a photo-consent field on
students, and without tagging no child is named on a photo.
"""

from __future__ import annotations

import datetime as dt
import io

from django.db import transaction
from django.db.models import Q
from django.utils import timezone
from PIL import Image
from rest_framework import status

from . import audit, dates, photos
from .clock import SchoolClock
from .enums import UserRole
from .errors import ApiError
from .models import ClassSection, GalleryEvent, GalleryPhoto, User
from .resources import section_label
from .scope import SchoolScope

MAX_PHOTOS = 20
MAX_BYTES = 5 * 1024 * 1024
MAX_SIDE = 1600
THUMB_SIDE = 400
FOLDER = "gallery-photos"
TITLE_MAX = 120
DESCRIPTION_MAX = 500
# An event is something that happened or is about to: a date a year either
# side of today is a typing slip.
DATE_RANGE = dt.timedelta(days=366)

ADMINS = (UserRole.SUPER_ADMIN, UserRole.GROUP_ADMIN, UserRole.SCHOOL_ADMIN)


class GalleryRefused(ApiError):
    status_code = status.HTTP_422_UNPROCESSABLE_ENTITY
    error_code = "GALLERY_REFUSED"


def refused(field: str, message: str) -> GalleryRefused:
    return GalleryRefused(message, {"errors": {field: [message]}})


# -- who may do what -----------------------------------------------------------


def is_admin(actor: User) -> bool:
    return actor.role in ADMINS


def visible_events(actor: User):
    """The school's events for an admin; for a teacher, the school-wide
    ones, their own classes' and whatever they posted."""
    rows = GalleryEvent.objects.all()
    if is_admin(actor):
        return SchoolScope.for_actor(actor).apply_to(rows)

    return rows.filter(school_id=actor.school_id).filter(
        Q(class_section__isnull=True) | Q(class_section__class_teacher_id=actor.id) | Q(posted_by_id=actor.id)
    )


def may_post_to(actor: User, school_id: int, section: ClassSection | None) -> bool:
    if is_admin(actor):
        return SchoolScope.for_actor(actor).allows(school_id)

    return section is not None and section.class_teacher_id == actor.id


def may_change(actor: User, event: GalleryEvent) -> bool:
    if is_admin(actor):
        return SchoolScope.for_actor(actor).allows(event.school_id)

    return event.posted_by_id == actor.id


def may_remove_photo(actor: User, photo: GalleryPhoto) -> bool:
    return may_change(actor, photo.gallery_event) or photo.uploaded_by_id == actor.id


# -- events ----------------------------------------------------------------------


def section_of(school_id: int, section_id) -> ClassSection | None:
    if section_id in (None, ""):
        return None

    section = ClassSection.objects.select_related("school_class").filter(
        pk=section_id, school_class__school_id=school_id
    ).first()
    if section is None:
        raise refused("class_section_id", "That class is not at this school.")

    return section


def checked(school_id: int, title, event_date: dt.date, description) -> tuple[str, str | None]:
    title = (title or "").strip()
    description = (description or "").strip() or None
    if not title or len(title) > TITLE_MAX:
        raise refused("title", f"Give the event a name of up to {TITLE_MAX} characters.")
    if description is not None and len(description) > DESCRIPTION_MAX:
        raise refused("description", f"Please keep the description to {DESCRIPTION_MAX} characters.")
    today = SchoolClock.for_school(school_id).now().date()
    if abs(event_date - today) > DATE_RANGE:
        raise refused("event_date", "Choose a date within a year of today.")

    return title, description


def create(actor: User, school_id: int, section_id, title, event_date: dt.date, description,
           request=None) -> GalleryEvent:
    section = section_of(school_id, section_id)
    if not may_post_to(actor, school_id, section):
        raise refused("class_section_id", "You can post only to a class you are the class teacher of.")
    title, description = checked(school_id, title, event_date, description)

    now = timezone.now()
    event = GalleryEvent.objects.create(
        school_id=school_id, class_section=section, title=title, event_date=event_date, description=description,
        posted_by=actor, created_at=now, updated_at=now,
    )
    audit.record(
        action="gallery.event_posted", module="communication", entity_type="gallery_event", entity_id=event.id,
        school_id=school_id,
        new={"title": title, "event_date": event_date.isoformat(), "class_section_id": section.id if section else None},
        request=request,
    )

    return event


def update(actor: User, event: GalleryEvent, section_id, title, event_date: dt.date, description,
           request=None) -> GalleryEvent:
    section = section_of(event.school_id, section_id)
    if not may_post_to(actor, event.school_id, section):
        raise refused("class_section_id", "You can post only to a class you are the class teacher of.")
    title, description = checked(event.school_id, title, event_date, description)

    old = {"title": event.title, "event_date": event.event_date.isoformat(),
           "class_section_id": event.class_section_id, "description": event.description}
    event.class_section, event.title, event.event_date, event.description = section, title, event_date, description
    event.updated_at = timezone.now()
    event.save(update_fields=["class_section", "title", "event_date", "description", "updated_at"])
    audit.record(
        action="gallery.event_changed", module="communication", entity_type="gallery_event", entity_id=event.id,
        school_id=event.school_id, old=old,
        new={"title": title, "event_date": event_date.isoformat(), "class_section_id": section.id if section else None,
             "description": description},
        request=request,
    )

    return event


def delete(event: GalleryEvent, request=None) -> None:
    paths = [p for row in event.photos.all() for p in (row.file_path, row.thumb_path)]
    old = {"title": event.title, "photos": len(paths) // 2}
    event_id, school_id = event.id, event.school_id
    with transaction.atomic():
        event.photos.all().delete()
        event.delete()
        audit.record(
            action="gallery.event_deleted", module="communication", entity_type="gallery_event", entity_id=event_id,
            school_id=school_id, old=old, request=request,
        )
    for path in paths:
        photos.remove(path)


# -- photos -------------------------------------------------------------------------


def thumbnail_of(data: bytes, extension: str) -> bytes:
    """The grid's copy, from the already re-encoded picture."""
    with Image.open(io.BytesIO(data)) as image:
        image.thumbnail((THUMB_SIDE, THUMB_SIDE))
        out = io.BytesIO()
        if extension == "jpg":
            image.convert("RGB").save(out, format="JPEG", quality=80, optimize=True)
        else:
            image.save(out, format="PNG", optimize=True)

    return out.getvalue()


def add_photo(actor: User, event: GalleryEvent, upload, request=None) -> GalleryPhoto:
    if GalleryPhoto.objects.filter(gallery_event_id=event.id).count() >= MAX_PHOTOS:
        raise refused("photo", f"An event can have at most {MAX_PHOTOS} photos.")

    try:
        data, extension = photos.prepare(upload, max_side=MAX_SIDE, max_bytes=MAX_BYTES)
    except photos.PhotoRejected as rejected:
        raise refused("photo", str(rejected))

    file_path = photos.store(data, extension, folder=FOLDER)
    thumb_path = photos.store(thumbnail_of(data, extension), extension, folder=FOLDER)
    now = timezone.now()
    photo = GalleryPhoto.objects.create(
        school_id=event.school_id, gallery_event=event, file_path=file_path, thumb_path=thumb_path,
        uploaded_by=actor, created_at=now, updated_at=now,
    )
    audit.record(
        action="gallery.photo_added", module="communication", entity_type="gallery_event", entity_id=event.id,
        school_id=event.school_id, new={"photo_id": photo.id}, request=request,
    )

    return photo


def remove_photo(photo: GalleryPhoto, request=None) -> None:
    paths = (photo.file_path, photo.thumb_path)
    photo_id, event_id, school_id = photo.id, photo.gallery_event_id, photo.school_id
    photo.delete()
    audit.record(
        action="gallery.photo_removed", module="communication", entity_type="gallery_event", entity_id=event_id,
        school_id=school_id, old={"photo_id": photo_id}, request=request,
    )
    for path in paths:
        photos.remove(path)


# -- parents ---------------------------------------------------------------------------


def events_for_children(children) -> "GalleryEvent.objects":
    """What a parent sees: each child's school's whole-school events and
    their classes' events, with at least one photo, newest first."""
    rule = Q(pk__in=[])
    for child in children:
        rule |= Q(school_id=child.school_id, class_section__isnull=True)
        if child.class_section_id:
            rule |= Q(school_id=child.school_id, class_section_id=child.class_section_id)

    return GalleryEvent.objects.filter(rule).filter(photos__isnull=False).distinct()


# -- what the screens read ---------------------------------------------------------------


def photo_resource(photo: GalleryPhoto, base: str) -> dict:
    return {"id": photo.id, "url": f"{base}/{photo.id}", "thumb_url": f"{base}/{photo.id}?size=thumb"}


def event_resource(event: GalleryEvent, actor: User | None = None, base: str = "/gallery-photos") -> dict:
    rows = sorted(event.photos.all(), key=lambda p: p.id)
    resource = {
        "id": event.id,
        "school_id": event.school_id,
        "title": event.title,
        "event_date": event.event_date.isoformat(),
        "date_label": dates.us(event.event_date),
        "description": event.description,
        "class_section": None if event.class_section_id is None else {
            "id": event.class_section_id, "name": section_label(event.class_section),
        },
        "photo_count": len(rows),
        "photos": [photo_resource(p, base) for p in rows],
    }
    if actor is not None:
        resource["posted_by"] = event.posted_by.name if event.posted_by_id else None
        resource["can_change"] = may_change(actor, event)

    return resource

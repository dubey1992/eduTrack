"""A student's photo (docs/student-photos.md, P1).

The checking and storing are the profile photo's (school/photos.py): the
upload is decoded and re-encoded, never trusted. A student's photo differs
in two ways: it is cut to a 3:4 passport shape around its centre (D2), the
shape of the box printed on admit cards and report cards, and it is kept a
little larger - 600 pixels on the longer side - so it prints sharp.

Only the current photo is kept. A new one replaces the file, and removing
one deletes it. Every change goes in the audit log, which records that the
photo changed and never the image.

**Bulk upload (P2)** matches each file to a student by its name: the part
before the extension is the admission number. A file name cannot hold a
`/`, and admission numbers often do, so `/`, `-` and `_` count as the same
character, and capitals do not matter (D1). Each file stands alone: one bad
file is reported and the rest are kept.
"""

from __future__ import annotations

from django.db import transaction
from django.utils import timezone

from . import audit, photos
from .models import Student

FOLDER = "student-photos"
MAX_SIDE = 600
ASPECT = (3, 4)

# Larger than a profile photo's 2 MB: a school's class photos come off a
# camera or a phone at 3-5 MB, and they are cut down to 600 pixels anyway.
MAX_BYTES = 5 * 1024 * 1024

# One bulk request. A CGI host answers small requests reliably
# (docs/deployment.md), so the app sends at most this many files at a time.
MAX_FILES_PER_BATCH = 10

# What a preview may ask about at once - more than any school's roll.
MAX_PREVIEW_NAMES = 3000

EXTENSIONS = (".jpg", ".jpeg", ".png")


def prepare(upload) -> tuple[bytes, str]:
    """The upload as a stored student photo will be: (bytes, extension).
    Raises photos.PhotoRejected with a sentence the person can act on."""
    return photos.prepare(upload, max_side=MAX_SIDE, max_bytes=MAX_BYTES, aspect=ASPECT)


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


# -- bulk upload: matching a file name to a student (P2) ---------------------

NOT_AN_IMAGE = "Only JPEG and PNG photos can be uploaded."
NO_STUDENT = "No student has this admission number."
TWO_STUDENTS = "More than one student matches this name. Upload this photo from the student's own page."
TWO_FILES = "Another file is for the same student. Keep one of them."


def match_key(text: str) -> str:
    """"SPHS/26/01A01", "sphs-26-01a01" and "SPHS_26_01A01" all give the
    same key (D1)."""
    key = text.strip().lower()

    for same in ("/", "_"):
        key = key.replace(same, "-")

    return key


def stem(file_name: str) -> str:
    """"ADM-1042.JPG" -> "ADM-1042". A path, if a browser sends one, is cut
    to the file's own name first."""
    name = file_name.replace(chr(92), "/").rsplit("/", 1)[-1]

    return name.rsplit(".", 1)[0] if "." in name else name


def is_image_name(file_name: str) -> bool:
    return file_name.strip().lower().endswith(EXTENSIONS)


def roll_by_key(school_id: int) -> dict[str, list[Student]]:
    """Every student of the school by match key - inactive ones too, since a
    returning student may be photographed. A key with two students is two
    admission numbers that differ only by `/`, `-`, `_` or capitals."""
    found: dict[str, list[Student]] = {}

    for student in Student.objects.filter(school_id=school_id).select_related("class_section__school_class"):
        found.setdefault(match_key(student.admission_number), []).append(student)

    return found


def class_name(student: Student) -> str | None:
    section = student.class_section

    if section is None:
        return None

    return f"{section.school_class.name} {section.name}".strip()


def preview(school_id: int, file_names: list[str]) -> dict:
    """What each file would do, judged from its name alone - nothing is
    uploaded to ask. `new` and `replace` will be uploaded; `not_an_image`,
    `unmatched`, `ambiguous` and `duplicate` will not."""
    roll = roll_by_key(school_id)
    rows = []

    for name in file_names:
        row = {"file_name": name, "status": None, "reason": None, "student": None}
        rows.append(row)

        if not is_image_name(name):
            row.update(status="not_an_image", reason=NOT_AN_IMAGE)
            continue

        matches = roll.get(match_key(stem(name)), [])

        if not matches:
            row.update(status="unmatched", reason=NO_STUDENT)
        elif len(matches) > 1:
            row.update(status="ambiguous", reason=TWO_STUDENTS)
        else:
            student = matches[0]
            row["status"] = "replace" if student.photo_path else "new"
            row["student"] = {
                "id": student.id,
                "name": student.name,
                "admission_number": student.admission_number,
                "class_section_name": class_name(student),
                "has_photo": bool(student.photo_path),
            }

    # Two files for one student: neither goes, since nobody can tell which
    # was meant.
    by_student: dict[int, list[dict]] = {}
    for row in rows:
        if row["student"] is not None:
            by_student.setdefault(row["student"]["id"], []).append(row)

    for same in by_student.values():
        if len(same) > 1:
            for row in same:
                row.update(status="duplicate", reason=TWO_FILES)

    counts: dict[str, int] = {}
    for row in rows:
        counts[row["status"]] = counts.get(row["status"], 0) + 1

    return {"rows": rows, "counts": counts}


def upload_batch(school_id: int, uploads: list, *, request=None) -> list[dict]:
    """Stores each file whose name matches exactly one student, and says what
    happened to every file. One bad file never stops the others. The batch
    is summed up in one audit row, beside each student's own."""
    roll = roll_by_key(school_id)
    done: set[int] = set()
    results = []

    for upload in uploads:
        name = str(upload.name)
        result = {"file_name": name, "status": "skipped", "reason": None, "student_id": None}
        results.append(result)

        if not is_image_name(name):
            result["reason"] = NOT_AN_IMAGE
            continue

        matches = roll.get(match_key(stem(name)), [])

        if len(matches) != 1:
            result["reason"] = NO_STUDENT if not matches else TWO_STUDENTS
            continue

        student = matches[0]
        result["student_id"] = student.id

        if student.id in done:
            result["reason"] = TWO_FILES
            continue

        try:
            data, extension = prepare(upload)
        except photos.PhotoRejected as rejected:
            result["reason"] = str(rejected)
            continue

        had_photo = bool(student.photo_path)
        set_photo(student, data, extension, request=request)
        done.add(student.id)
        result["status"] = "replaced" if had_photo else "added"

    counts = {status: sum(1 for r in results if r["status"] == status) for status in ("added", "replaced", "skipped")}
    audit.record(
        action="student_photos.bulk_uploaded", module="students", entity_type="school",
        entity_id=school_id, school_id=school_id, new=counts, request=request,
    )

    return results

"""Photos on a daily teaching report (docs/mobile-apps-review.md, M9, 6.6).

Decided by the owner 2026-11-24: up to three per report, seen by staff only
- the teacher, their HOD and the school's admins; parents never.

The author adds and removes them until the report is reviewed: a reviewed
report stays what the HOD reviewed. Each photo is decoded and re-encoded
(school/photos.py), so nothing that rode along in the camera file is kept,
and read back only through the authenticated endpoint.
"""

from __future__ import annotations

from django.utils import timezone

from . import audit, photos
from .models import DailyTeachingReport, TeachingReportPhoto

MAX_PHOTOS = 3
MAX_BYTES = 5 * 1024 * 1024
# Enough to read a board from across the room, small enough for a phone.
MAX_SIDE = 1600
FOLDER = "teaching-report-photos"


class ReportPhotoRefused(Exception):
    """Why the photo cannot be added. The message is for the person."""


def add(report: DailyTeachingReport, upload, request=None) -> TeachingReportPhoto:
    if report.reviewed_by_id is not None:
        raise ReportPhotoRefused("This report has been reviewed, so its photos stay as they were.")

    if TeachingReportPhoto.objects.filter(daily_teaching_report_id=report.id).count() >= MAX_PHOTOS:
        raise ReportPhotoRefused(f"A report can carry at most {MAX_PHOTOS} photos.")

    try:
        data, extension = photos.prepare(upload, max_side=MAX_SIDE, max_bytes=MAX_BYTES)
    except photos.PhotoRejected as rejected:
        raise ReportPhotoRefused(str(rejected))

    now = timezone.now()
    photo = TeachingReportPhoto.objects.create(
        school_id=report.school_id,
        daily_teaching_report_id=report.id,
        file_path=photos.store(data, extension, folder=FOLDER),
        created_at=now,
        updated_at=now,
    )
    audit.record(
        action="teaching_report.photo_added", module="teaching_reports", entity_type="daily_teaching_report",
        entity_id=report.id, school_id=report.school_id, new={"photo_id": photo.id}, request=request,
    )

    return photo


def remove(report: DailyTeachingReport, photo: TeachingReportPhoto, request=None) -> None:
    if report.reviewed_by_id is not None:
        raise ReportPhotoRefused("This report has been reviewed, so its photos stay as they were.")

    path = photo.file_path
    photo.delete()
    audit.record(
        action="teaching_report.photo_removed", module="teaching_reports", entity_type="daily_teaching_report",
        entity_id=report.id, school_id=report.school_id, old={"photo_id": photo.id}, request=request,
    )
    photos.remove(path)


def resource(photo: TeachingReportPhoto) -> dict:
    return {"id": photo.id, "url": f"/teaching-reports/{photo.daily_teaching_report_id}/photos/{photo.id}"}


def of_report(report: DailyTeachingReport) -> list[dict]:
    """The report's photos, oldest first, from the list's prefetch when there is one."""
    return [resource(photo) for photo in sorted(report.photos.all(), key=lambda photo: photo.id)]

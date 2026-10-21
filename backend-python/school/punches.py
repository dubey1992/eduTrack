"""Punches from the fingerprint devices (docs/biometric.md, B2).

A device reports an id it knows and a wall-clock time at the school, and
nothing else of use. Three consequences shape everything here:

- **The id is the device's, not ours.** It is mapped to a staff profile where
  somebody has said which, and left unattached where nobody has. An unmapped
  punch is recorded and shown, never dropped: the first anybody should know of
  a missing enrolment is a row saying so, not a register with nothing in it.
- **The time has no zone.** It is wall clock at the school, so the school's own
  timezone turns it into an instant (docs/timezones.md). A server that assumed
  its own zone would move every punch for any school far enough east or west.
- **The same punch arrives more than once.** Devices resend, and an uploaded
  export usually overlaps days already pushed. A repeat is a repeat, not an
  error, and it lands once.

Nothing here touches the staff register. Filling check-in and check-out is B3,
and keeping that a separate step is what lets a school load months of history
without rewriting months of attendance.
"""

from __future__ import annotations

import datetime as dt
import zoneinfo

from django.db import IntegrityError, transaction
from django.utils import timezone

from . import dates
from .clock import SchoolClock
from .models import BiometricPunch, StaffProfile

DEVICE = "device"
UPLOAD = "upload"

# Beyond this a file is somebody's whole year, and a CSV is the wrong shape
# for it. Matches the bulk importer's own ceiling for the same reason.
MAX_PUNCHES = 2000


class Outcome:
    """What became of a batch. The same three words the trip sync uses, so
    two endpoints that both absorb a device's backlog read alike."""

    def __init__(self) -> None:
        self.accepted = 0
        self.duplicate = 0
        self.refused: list[str] = []

    def as_dict(self) -> dict:
        return {"accepted": self.accepted, "duplicate": self.duplicate, "refused": self.refused}


def record(school_id: int, rows: list[dict], *, source: str = UPLOAD, device=None) -> Outcome:
    """Stores what makes sense and counts the rest.

    `rows` are `{biometric_user_id, punched_at (naive local), raw}`. Each is
    taken on its own: one unreadable line does not throw away the file, which
    matters when the file is a month of somebody's attendance.
    """
    outcome = Outcome()
    clock = SchoolClock.for_school(school_id)
    zone = zoneinfo.ZoneInfo(clock.timezone())
    enrolled = _enrolment(school_id)
    now = timezone.now()

    for row in rows:
        local = row["punched_at"]

        if local.tzinfo is not None:
            local = local.astimezone(zone)
        else:
            local = local.replace(tzinfo=zone)

        punch = BiometricPunch(
            school_id=school_id,
            device=device,
            biometric_user_id=row["biometric_user_id"],
            staff_profile_id=enrolled.get(row["biometric_user_id"]),
            punched_at=local.astimezone(dt.timezone.utc),
            local_date=local.date(),
            source=source,
            raw=(row.get("raw") or "")[:255] or None,
            created_at=now,
            updated_at=now,
        )

        try:
            # Its own transaction, so one duplicate does not poison the rest
            # of the batch - PostgreSQL refuses every later statement in a
            # transaction once one has failed.
            with transaction.atomic():
                punch.save()
        except IntegrityError:
            outcome.duplicate += 1
            continue

        outcome.accepted += 1

    return outcome


def _enrolment(school_id: int) -> dict[str, int]:
    """Device id to staff profile, for one school. One query for a whole
    batch rather than one per punch."""
    return {
        found: pk
        for pk, found in StaffProfile.objects.filter(
            school_id=school_id, biometric_user_id__isnull=False
        ).values_list("id", "biometric_user_id")
    }


def attach_waiting(profile: StaffProfile) -> int:
    """Attaches punches that arrived before anybody said whose they were.

    Without this, enrolling somebody fixes only the future: every punch that
    came in while the id was unmapped stays unattached for ever, and the
    register for those days stays empty with no way to put it right short of
    re-uploading the file.

    Returns how many were attached, because the screen that enrolled them
    should be able to say so.
    """
    if not profile.biometric_user_id:
        return 0

    return BiometricPunch.objects.filter(
        school_id=profile.school_id,
        biometric_user_id=profile.biometric_user_id,
        staff_profile__isnull=True,
    ).update(staff_profile_id=profile.pk, updated_at=timezone.now())


def detach(profile: StaffProfile, previous: str | None) -> int:
    """Lets go of punches that are no longer theirs.

    The other half of [attach_waiting]: an id typed in error and corrected
    must not leave somebody else's punches on this person's register. They go
    back to unattached rather than being deleted - they are still real
    punches by whoever that id belongs to.
    """
    if not previous or previous == profile.biometric_user_id:
        return 0

    return BiometricPunch.objects.filter(
        school_id=profile.school_id,
        biometric_user_id=previous,
        staff_profile_id=profile.pk,
    ).update(staff_profile_id=None, updated_at=timezone.now())


# -- reading a file a device exported ----------------------------------------
#
# Two columns and nothing else: who, and when. Device software exports a
# dozen more - verify mode, work code, the reader's own name - and none of
# them change what goes on a register, so asking for them would be asking
# somebody to tidy a file for no reason.
HEADINGS = ("biometric_user_id", "punched_at")

# The one date order this product reads and writes (school/dates.py), and a
# 24-hour clock for the time - that is what device exports carry, and an
# am/pm somebody has to retype is a chance to get it wrong.
#
# Built from dates.DATE rather than spelled out: the format lives in one
# place because a copy of it drifted once, and the message log spent a year
# comparing the server's 09/16/2026 against a screen's "16 Sep 2026".
PUNCH_FORMAT = dates.DATE + " %H:%M"
PUNCH_FORMAT_SECONDS = PUNCH_FORMAT + ":%S"


def parse_csv(upload) -> tuple[list[dict], list[str]]:
    """The uploaded file as rows, and everything wrong with it.

    Every bad line is reported rather than only the first, so one upload
    tells somebody all of it - the same courtesy the bulk importer extends.
    Unlike that importer, **a bad line does not throw away the file**: a
    month of attendance should not be refused because one row of it is
    unreadable, and the rows that are fine are worth having.
    """
    import csv
    import io

    try:
        raw = upload.read()
    except OSError:
        return [], ["The file could not be read."]

    # utf-8-sig, because a byte order mark is what a spreadsheet writes and
    # the first column name would otherwise never match.
    reader = csv.reader(io.StringIO(raw.decode("utf-8-sig", errors="replace")))

    try:
        headings = [heading.strip() for heading in next(reader)]
    except StopIteration:
        return [], ["The file is empty."]

    if tuple(headings) != HEADINGS:
        return [], ["The column headings must be: " + ", ".join(HEADINGS) + "."]

    rows: list[dict] = []
    problems: list[str] = []
    line = 1

    for values in reader:
        line += 1

        if not any((value or "").strip() for value in values):
            continue

        if len(rows) >= MAX_PUNCHES:
            problems.append(f"Only the first {MAX_PUNCHES} punches were read; split the file and upload the rest.")
            break

        values = (list(values) + ["", ""])[:2]
        who = (values[0] or "").strip()
        when = (values[1] or "").strip()

        if not who:
            problems.append(f"Line {line}: no biometric id.")
            continue

        if len(who) > 32:
            problems.append(f"Line {line}: the biometric id is too long.")
            continue

        moment = _read_time(when)

        if moment is None:
            problems.append(f"Line {line}: '{when}' is not a date and time (m/d/Y H:i).")
            continue

        rows.append({"biometric_user_id": who, "punched_at": moment, "raw": f"{who},{when}"})

    return rows, problems


def _read_time(value: str) -> dt.datetime | None:
    """A device's wall-clock stamp, with or without seconds. Naive on
    purpose: the zone belongs to the school, not to the file."""
    for shape in (PUNCH_FORMAT_SECONDS, PUNCH_FORMAT):
        try:
            return dt.datetime.strptime(value, shape)
        except ValueError:
            continue

    return None

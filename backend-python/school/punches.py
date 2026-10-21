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

Filling the register is a separate step on purpose - see `fill_register` at
the bottom of this module. A punch only ever writes a time, never a status,
and never a row that was not already there.
"""

from __future__ import annotations

import datetime as dt
import zoneinfo

from django.db import IntegrityError, models, transaction
from django.utils import timezone

from . import audit, dates
from .clock import SchoolClock
from .fields import as_utc
from .models import BiometricPunch, StaffAttendance, StaffProfile

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

        # Register rows whose times these punches filled in. Worth saying
        # out loud: "40 new" and "nothing reached the register" is a
        # sentence somebody needs to see, because it usually means nobody
        # has been enrolled on the device yet.
        self.register_filled = 0

    def as_dict(self) -> dict:
        return {
            "accepted": self.accepted,
            "duplicate": self.duplicate,
            "refused": self.refused,
            "register_filled": self.register_filled,
        }


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
    landed: list[tuple[int | None, dt.date]] = []

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
        landed.append((punch.staff_profile_id, punch.local_date))

    outcome.register_filled = fill_register(school_id, landed)

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


# -- the register ------------------------------------------------------------
#
# The earliest punch of a local day is the check-in and the latest is the
# check-out (docs/biometric.md). Three rules make that safe to run over
# months of uploaded history:
#
# - **No row is created.** Creating one would mean choosing a status, which
#   is the one thing these punches cannot know. A day nobody has marked
#   stays unmarked; the marking screen pre-fills the times from the punches
#   instead, so whoever sets the status sees what the device saw.
# - **Times are set, never cleared.** A day with no punches is left exactly
#   as it is. That also means a corrected enrolment leaves the old times
#   behind for a human to fix, which is the lesser of the two wrongs:
#   silently blanking a time somebody typed is worse.
# - **One punch fills the check-in only.** Somebody who touched the reader
#   once arrived; nothing says when they left, and a check-out equal to the
#   check-in would read as a day of no work at all.


def register_times(school_id: int, date, profile_ids) -> dict[int, dict]:
    """First and last punch of one local day, per person, on the school's
    own clock - which is the clock the register is read in."""
    profile_ids = [pk for pk in profile_ids if pk]

    if not profile_ids:
        return {}

    zone = zoneinfo.ZoneInfo(SchoolClock.for_school(school_id).timezone())
    found = (
        BiometricPunch.objects.filter(school_id=school_id, local_date=date, staff_profile_id__in=profile_ids)
        .values("staff_profile_id")
        .annotate(first=models.Min("punched_at"), last=models.Max("punched_at"))
    )

    times = {}

    for row in found:
        first = as_utc(row["first"]).astimezone(zone).time().replace(second=0, microsecond=0)
        last = as_utc(row["last"]).astimezone(zone).time().replace(second=0, microsecond=0)

        times[row["staff_profile_id"]] = {"check_in": first, "check_out": last if last != first else None}

    return times


def fill_register(school_id: int, landed) -> int:
    """Puts the day's first and last punch on the register rows that exist.

    `landed` is (staff_profile_id, local_date) pairs - whatever just arrived,
    or just became attributed to somebody. Returns how many rows changed, so
    an upload can say whether any of it reached the register at all.
    """
    wanted: dict[dt.date, set[int]] = {}

    for profile_id, date in landed:
        if profile_id:
            wanted.setdefault(date, set()).add(profile_id)

    filled = 0

    for date, profile_ids in wanted.items():
        times = register_times(school_id, date, profile_ids)
        touched = []

        for row in StaffAttendance.objects.filter(
            school_id=school_id, attendance_date=date, staff_profile_id__in=profile_ids
        ):
            want = times.get(row.staff_profile_id)

            if want is None:
                continue

            check_in = want["check_in"]
            check_out = want["check_out"] or row.check_out

            if row.check_in == check_in and row.check_out == check_out:
                continue

            row.check_in = check_in
            row.check_out = check_out
            row.updated_at = timezone.now()
            row.save(update_fields=["check_in", "check_out", "updated_at"])
            touched.append(row.staff_profile_id)

        if touched:
            # Attendance changes are audited (CLAUDE.md 13). One entry per
            # day rather than per row: a month's upload is one action by one
            # person, and a hundred near-identical rows would bury it.
            audit.record(
                action="staff_attendance.times_from_device",
                module="staff_attendance",
                entity_type="school",
                entity_id=school_id,
                school_id=school_id,
                new={"attendance_date": str(date), "staff_profile_ids": sorted(touched)},
            )

        filled += len(touched)

    return filled


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

    waiting = BiometricPunch.objects.filter(
        school_id=profile.school_id,
        biometric_user_id=profile.biometric_user_id,
        staff_profile__isnull=True,
    )
    # Read the days before the update, while the rows are still findable by
    # the id nobody was mapped to.
    days = list(waiting.values_list("local_date", flat=True).distinct())
    attached = waiting.update(staff_profile_id=profile.pk, updated_at=timezone.now())

    if attached:
        # The register too, not just the log: a day that was already marked
        # while this person was unenrolled should now show the times the
        # device had for them all along.
        fill_register(profile.school_id, [(profile.pk, day) for day in days])

    return attached


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

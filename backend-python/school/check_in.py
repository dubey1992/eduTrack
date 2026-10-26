"""Checking in and out from the phone (docs/staff-check-in.md).

A member of staff marks their own arrival and departure on the staff
register, where a school has no fingerprint readers - or alongside them.
The proof is place: the phone's location has to be within the school's
radius (100 m unless the school says otherwise) of the school's own pin.

What a check-in does, decided 2026-10-25:
- it marks the day **present**, with the time;
- a check-out records the leaving time, and may be done again - the last
  one stands, the way the latest fingerprint punch does;
- **late** is not a status: it is derived on the register from the school's
  first period, exactly as for punches and for the office's own marks.

What the hourly job does with a forgotten check-out (decided 2026-10-26):
once the person's own school day is over, it records the leaving time as the
school's closing time - the end of the last period, on a half day the half
day's - and notes on the register that the time was not recorded, for the
office to review. Only for a day the person checked in themselves (or a
reader did), within the last week; a day the office marked is the office's,
and a day with no bell schedule, or a check-in after the last bell, has no
closing time to give, so it is left open for the office.

What it refuses, each with its own code so the app can say exactly why:
a closed day or a holiday, approved leave, a school with no pin on the map,
a location another app is inventing (a mock location), a fix too old or too
vague to judge, a phone too far away, a second check-in, and a check-out
before any check-in.

Edge cases decided 2026-10-25 (docs/staff-check-in.md, "Edge cases"):
- **Half-day leave** does not refuse: the person works the other half, so
  checking in makes the day a half day - which is how payroll already counts
  a half-day leave (half present, half leave).
- **Two taps at once**, from two phones, land once: the second is told the
  day is already checked in, never a server error.
- **A fingerprint punch first**: the second check-in is told the reader has
  it, so nobody thinks the app lost their tap.
- **A forgotten check-out** is not fixable from the app the next day - the
  leaving time is not knowable - so the app is told about the open day and
  says to ask the office. The office can still correct anything on
the register afterwards; a self check-in is a mark like any other.

The location itself is never stored - only how far from school it was, in
the audit log, which is what anybody reviewing a disputed day needs.
"""

from __future__ import annotations

import datetime as dt

from django.db import IntegrityError, transaction
from django.db.models import Max
from django.utils import timezone

from . import audit, geo, modules, week, working_hours
from .clock import SchoolClock
from .enums import LeaveStatus, LeaveType, StaffAttendanceStatus
from .errors import ApiError, ModuleDisabled, NoStaffRecord
from .models import AuditLog, Period, School, StaffAttendance, StaffLeave, StaffProfile, User
from .services import AttendanceService, HolidayService, _is_late, holiday_summary

MODULE = "staff_attendance"

# How old a location fix may be, in seconds, and still count as "now".
STALE_AFTER_S = 120

# How far back a forgotten check-out is still mentioned.
UNFINISHED_LOOKBACK_DAYS = 7

# What the register says about a day the hourly job closed.
AUTO_CLOSED_NOTE = "Check-out not recorded - closed at school closing time."


class CheckInRefused(ApiError):
    """A check-in or check-out the rules do not allow. 422, with a code per
    reason (see the module docstring)."""

    status_code = 422

    def __init__(self, code: str, message: str, details: dict | None = None) -> None:
        super().__init__(message, details)
        self.error_code = code


def profile_of(actor: User) -> StaffProfile:
    profile = StaffProfile.objects.filter(user_id=actor.id).first()

    if profile is None or actor.school_id is None:
        raise NoStaffRecord("Checking in is for members of a school's staff.")

    return profile


def _settings(school_id) -> tuple[bool, int]:
    """Whether this school lets staff check in from the app, and how close
    to the school they must be. Off with the Staff Attendance module."""
    return (
        modules.is_enabled(school_id, MODULE) and bool(modules.setting(school_id, MODULE, "app_check_in")),
        int(modules.setting(school_id, MODULE, "check_in_radius_m")),
    )


def _approved_leave(profile: StaffProfile, date) -> StaffLeave | None:
    return StaffLeave.objects.filter(
        staff_profile_id=profile.id, status=LeaveStatus.APPROVED, start_date__lte=date, end_date__gte=date
    ).first()


def _leave_today(profile: StaffProfile, today, row: StaffAttendance | None) -> tuple[bool, bool]:
    """(on leave for the whole day, on approved half-day leave).

    Approving leave writes `leave` on the register even for a half day
    (StaffLeaveService.sync_attendance), so the register alone cannot tell
    the two apart; the approved request can."""
    leave = _approved_leave(profile, today)
    half = leave is not None and leave.leave_type == LeaveType.HALF_DAY
    full = not half and (leave is not None or (row is not None and row.status == StaffAttendanceStatus.LEAVE))

    return full, half


def _row(profile: StaffProfile, date) -> StaffAttendance | None:
    return StaffAttendance.objects.filter(staff_profile_id=profile.id, attendance_date=date).first()


def _assert_place(school: School, latitude, longitude, accuracy_m, radius: int, is_mocked=False, fix_age_s=None) -> int:
    """The phone has to be within the radius of the school's pin. Returns
    how far it was, rounded to the metre."""
    if school.latitude is None or school.longitude is None:
        raise CheckInRefused(
            "NO_SCHOOL_LOCATION",
            "Your school has not set its location yet, so the app cannot check you in. Ask the office.",
        )

    # Android says when the position comes from another app rather than the
    # satellites - a "fake GPS" app, or a developer's test tool. That is not a
    # place, whatever its distance.
    if is_mocked:
        raise CheckInRefused(
            "LOCATION_MOCKED",
            "Your phone is using a location set by another app (a mock location). "
            "Turn that app off, then check in again.",
        )

    # A position the phone remembered from earlier is where somebody was,
    # not where they are.
    if fix_age_s is not None and fix_age_s > STALE_AFTER_S:
        raise CheckInRefused(
            "LOCATION_STALE",
            "Your phone's location is out of date. Wait a few seconds for it to update, then try again.",
            {"fix_age_s": round(fix_age_s)},
        )

    # A fix that could be anywhere within a few hundred metres says nothing
    # about whether somebody is inside the gate; asking again outdoors or by
    # a window usually tightens it.
    if accuracy_m is not None and accuracy_m > radius:
        raise CheckInRefused(
            "LOCATION_TOO_VAGUE",
            f"Your phone's location is only accurate to {round(accuracy_m)} m. "
            "Step outside or near a window and try again.",
            {"accuracy_m": round(accuracy_m)},
        )

    distance = round(geo.distance_m(latitude, longitude, school.latitude, school.longitude))

    if distance > radius:
        raise CheckInRefused(
            "OUTSIDE_SCHOOL",
            f"You are {distance} m from school. Check in when you are within {radius} m.",
            {"distance_m": distance, "radius_m": radius},
        )

    return distance


def _assert_day(profile: StaffProfile, today, row: StaffAttendance | None) -> bool:
    """Refuses a closed day and a day of leave. Returns whether the person
    is on approved half-day leave, which does not refuse."""
    AttendanceService.assert_school_is_open(profile.school_id, today)

    full, half = _leave_today(profile, today, row)

    if full:
        raise CheckInRefused("ON_LEAVE", "You are on leave today, so there is nothing to check in to.")

    return half


def _assert_enabled(school_id) -> None:
    if not modules.is_enabled(school_id, MODULE):
        raise ModuleDisabled(modules.get(MODULE).label)

    enabled, _ = _settings(school_id)

    if not enabled:
        raise CheckInRefused("CHECK_IN_OFF", "Your school marks staff attendance in the office, not from the app.")


def _already_in(row: StaffAttendance):
    """Refuses a second check-in, saying where the first one came from."""
    at = working_hours.clock(row.check_in)

    if row.marked_by_id is None:
        raise CheckInRefused(
            "ALREADY_CHECKED_IN", f"The fingerprint reader already checked you in at {at} today."
        )

    raise CheckInRefused("ALREADY_CHECKED_IN", f"You checked in at {at} today.")


def _unfinished_day(profile: StaffProfile, actor: User, today) -> dict | None:
    """The latest recent day this person checked themselves in and never
    out - so the app can say so. Only their own check-ins: a day the office
    marked is the office's to complete."""
    row = (
        StaffAttendance.objects.filter(
            staff_profile_id=profile.id,
            attendance_date__lt=today,
            attendance_date__gte=today - dt.timedelta(days=UNFINISHED_LOOKBACK_DAYS),
            check_in__isnull=False,
            check_out__isnull=True,
            marked_by_id=actor.id,
        )
        .order_by("-attendance_date")
        .first()
    )

    if row is None:
        return None

    return {"date": row.attendance_date.isoformat(), "check_in": working_hours.clock(row.check_in)}


def closing_time(school: School, date) -> dt.time | None:
    """When the school's last bell ends on that date: the end of its last
    period of the day's shape - a Saturday half day ends earlier. None when
    the school has no bell schedule for it."""
    shape = week.WorkingWeek(school.working_days).shape_on(date) or week.FULL_DAY

    return Period.objects.filter(school_id=school.id, day_shape=shape).aggregate(last=Max("end_time"))["last"]


def close_forgotten_check_outs(now=None) -> int:
    """Closes the days somebody checked into and never out, once their own
    school's day is over, at the school's closing time - with a note on the
    register for the office to review. Returns how many it closed.

    Run hourly (the close_open_trips command), because every school's
    midnight is its own.
    """
    now = now or timezone.now()
    closed = 0
    closing_times: dict[tuple[int, dt.date], dt.time | None] = {}

    # A day either side of the lookback, to be decided per school below.
    earliest = now.date() - dt.timedelta(days=UNFINISHED_LOOKBACK_DAYS + 1)
    open_days = StaffAttendance.objects.select_related("school", "staff_profile").filter(
        attendance_date__gte=earliest, check_in__isnull=False, check_out__isnull=True
    )

    for row in open_days:
        clock = SchoolClock.for_school(row.school)
        today = clock.now().date()

        # Still the day where the school is - they may yet check out - or
        # longer ago than anybody is still told about.
        if now < clock.end_of_day_utc(row.attendance_date):
            continue
        if row.attendance_date < today - dt.timedelta(days=UNFINISHED_LOOKBACK_DAYS):
            continue

        # The person's own check-in, or a reader's. A time the office wrote
        # in is the office's to complete.
        if row.marked_by_id not in (None, row.staff_profile.user_id):
            continue

        key = (row.school_id, row.attendance_date)
        if key not in closing_times:
            closing_times[key] = closing_time(row.school, row.attendance_date)
        closes_at = closing_times[key]

        if closes_at is None or closes_at <= row.check_in:
            continue

        remarks = f"{row.remarks} {AUTO_CLOSED_NOTE}" if row.remarks else AUTO_CLOSED_NOTE

        with transaction.atomic():
            # Only if still open: the office may have corrected it meanwhile.
            updated = StaffAttendance.objects.filter(pk=row.pk, check_out__isnull=True).update(
                check_out=closes_at, remarks=remarks[:255], updated_at=timezone.now()
            )
            if not updated:
                continue

            audit.record(
                actor=None, action="staff_attendance.auto_closed", module="staff_attendance",
                entity_type="staff_attendance", entity_id=row.id, school_id=row.school_id,
                old={"check_out": None},
                new={"attendance_date": row.attendance_date.isoformat(), "check_out": closes_at.strftime("%H:%M")},
            )
        closed += 1

    return closed


class CheckInService:
    """The three things a person can do with their own day: see it, check
    in, check out. Every write is audited (test_audit_trail_api sweeps this
    class)."""

    @staticmethod
    def today_for(actor: User) -> dict:
        """Where the caller stands today, and what the app may offer them."""
        profile = profile_of(actor)
        school_id = profile.school_id
        clock = SchoolClock.for_school(school_id)
        now = clock.now()
        today = now.date()

        enabled, radius = _settings(school_id)
        school = School.objects.get(pk=school_id)
        has_pin = school.latitude is not None and school.longitude is not None
        holiday = HolidayService.holiday_on(school_id, today)
        is_open = holiday is None and HolidayService.is_working_day(school_id, today)
        row = _row(profile, today)
        on_leave, half_day_leave = _leave_today(profile, today, row)

        check_in = working_hours.clock(row.check_in) if row and row.check_in else None
        check_out = working_hours.clock(row.check_out) if row and row.check_out else None
        late_after = Period.objects.filter(school_id=school_id).order_by("start_time").values_list("start_time", flat=True).first()

        reason = None
        if not enabled:
            reason = "Your school marks staff attendance in the office, not from the app."
        elif not is_open:
            reason = f"No attendance today: {holiday.name}." if holiday else "The school is closed today."
        elif on_leave:
            reason = "You are on leave today."
        elif not has_pin:
            reason = "Your school has not set its location yet, so the app cannot check you in. Ask the office."

        return {
            "date": today.isoformat(),
            "now": now.strftime("%H:%M"),
            "enabled": enabled,
            "radius_m": radius,
            "school_day": {"is_open": is_open, "holiday": holiday_summary(holiday) if holiday else None},
            "on_leave": on_leave,
            "half_day_leave": half_day_leave,
            "status": row.status if row else None,
            "check_in": check_in,
            "check_out": check_out,
            "late": _is_late(row.check_in if row else None, late_after),
            "working_hours": working_hours.format_span(check_in, check_out),
            # Somebody other than the person themselves put this row there - the
            # office or a reader on the wall - which the app says, so a teacher
            # who finds themselves marked absent knows who to ask.
            "marked_by_someone_else": row is not None and row.marked_by_id != actor.id,
            "can_check_in": reason is None and check_in is None,
            "can_check_out": reason is None and check_in is not None,
            "blocked_reason": reason,
            "unfinished_day": _unfinished_day(profile, actor, today),
        }

    @staticmethod
    def check_in(actor: User, latitude, longitude, accuracy_m=None, is_mocked=False, fix_age_s=None) -> dict:
        profile = profile_of(actor)
        school_id = profile.school_id
        _assert_enabled(school_id)

        now = SchoolClock.for_school(school_id).now()
        today = now.date()
        _, radius = _settings(school_id)

        with transaction.atomic():
            row = StaffAttendance.objects.select_for_update().filter(
                staff_profile_id=profile.id, attendance_date=today
            ).first()
            half_day_leave = _assert_day(profile, today, row)

            if row is not None and row.check_in is not None:
                _already_in(row)

            distance = _assert_place(
                School.objects.get(pk=school_id), latitude, longitude, accuracy_m, radius, is_mocked, fix_age_s
            )
            at = now.time().replace(second=0, microsecond=0)
            stamp = timezone.now()
            arriving_status = StaffAttendanceStatus.HALF_DAY if half_day_leave else StaffAttendanceStatus.PRESENT

            if row is None:
                try:
                    # Its own savepoint: a second phone that created the row a
                    # moment ago fails here alone, and is told the truth.
                    with transaction.atomic():
                        row = StaffAttendance.objects.create(
                            school_id=school_id, staff_profile_id=profile.id, attendance_date=today,
                            status=arriving_status, check_in=at, marked_by_id=actor.id,
                            created_at=stamp, updated_at=stamp,
                        )
                except IntegrityError:
                    _already_in(StaffAttendance.objects.get(staff_profile_id=profile.id, attendance_date=today))
                before = None
            else:
                # The office marked the day first - absent before they arrived,
                # or half a day. Being here, provably, makes an absent day a
                # present one; any other status the office chose stands. A
                # half-day leave's `leave` mark becomes the half day worked.
                before = {"status": row.status, "check_in": None}
                if row.status in (StaffAttendanceStatus.ABSENT, StaffAttendanceStatus.LEAVE):
                    row.status = arriving_status
                row.check_in = at
                row.marked_by_id = actor.id
                row.updated_at = stamp
                row.save(update_fields=["status", "check_in", "marked_by_id", "updated_at"])

            audit.record(
                action="staff_attendance.checked_in", module="staff_attendance", entity_type="staff_attendance",
                entity_id=row.id, school_id=school_id, old=before,
                new={"attendance_date": today.isoformat(), "status": row.status, "check_in": at.strftime("%H:%M"),
                     "distance_m": distance},
            )

        return CheckInService.today_for(actor)


    @staticmethod
    def check_out(actor: User, latitude, longitude, accuracy_m=None, is_mocked=False, fix_age_s=None) -> dict:
        profile = profile_of(actor)
        school_id = profile.school_id
        _assert_enabled(school_id)

        now = SchoolClock.for_school(school_id).now()
        today = now.date()
        _, radius = _settings(school_id)

        with transaction.atomic():
            row = StaffAttendance.objects.select_for_update().filter(
                staff_profile_id=profile.id, attendance_date=today
            ).first()
            _assert_day(profile, today, row)

            if row is None or row.check_in is None:
                raise CheckInRefused("NOT_CHECKED_IN", "Check in first - there is no arrival to check out from.")

            distance = _assert_place(
                School.objects.get(pk=school_id), latitude, longitude, accuracy_m, radius, is_mocked, fix_age_s
            )
            at = now.time().replace(second=0, microsecond=0)
            before = {"check_out": working_hours.clock(row.check_out)} if row.check_out else None

            # Again is allowed: somebody who checked out and came back for a
            # meeting leaves later, and the last time is the one that is true.
            row.check_out = at
            row.updated_at = timezone.now()
            row.save(update_fields=["check_out", "updated_at"])

            audit.record(
                action="staff_attendance.checked_out", module="staff_attendance", entity_type="staff_attendance",
                entity_id=row.id, school_id=school_id, old=before,
                new={"attendance_date": today.isoformat(), "check_out": at.strftime("%H:%M"), "distance_m": distance},
            )

        return CheckInService.today_for(actor)

    @staticmethod
    def log(actor: User, school_id: int, department_id, date) -> list[dict]:
        """Every check-in and check-out made from the app on one day, in the
        order they happened, for the people the actor may see on the staff
        register (an HOD: their departments). Read from the audit trail, which
        is where each one is recorded with the distance from school.

        The times are as recorded at the tap. If the office later corrected
        the register, the register shows the correction; this shows what the
        phone said, which is what somebody looking into a disputed day needs.
        """
        from .services import StaffAttendanceService

        staff = {
            profile.id: profile
            for profile in StaffAttendanceService.roster(school_id, department_id, actor)
        }
        rows = {
            row.id: row.staff_profile_id
            for row in StaffAttendance.objects.filter(
                school_id=school_id, attendance_date=date, staff_profile_id__in=list(staff)
            )
        }
        entries = AuditLog.objects.filter(
            school_id=school_id,
            entity_type="staff_attendance",
            entity_id__in=list(rows),
            action__in=("staff_attendance.checked_in", "staff_attendance.checked_out"),
        ).order_by("created_at", "id")

        events = []
        for entry in entries:
            profile = staff[rows[int(entry.entity_id)]]
            arriving = entry.action == "staff_attendance.checked_in"
            new = entry.new_values or {}
            events.append({
                "id": entry.id,
                "staff_profile_id": profile.id,
                "name": profile.user.name,
                "employee_id": profile.employee_id,
                "department_name": profile.department.name if profile.department_id else None,
                "kind": "check_in" if arriving else "check_out",
                "time": new.get("check_in" if arriving else "check_out"),
                "distance_m": new.get("distance_m"),
            })

        return events

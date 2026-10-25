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

What it refuses, each with its own code so the app can say exactly why:
a closed day or a holiday, approved leave, a school with no pin on the map,
a fix too vague to judge, a phone too far away, a second check-in, and a
check-out before any check-in. The office can still correct anything on
the register afterwards; a self check-in is a mark like any other.

The location itself is never stored - only how far from school it was, in
the audit log, which is what anybody reviewing a disputed day needs.
"""

from __future__ import annotations

from django.db import transaction
from django.utils import timezone

from . import audit, geo, modules, working_hours
from .clock import SchoolClock
from .enums import LeaveStatus, StaffAttendanceStatus
from .errors import ApiError, ModuleDisabled, NoStaffRecord
from .models import Period, School, StaffAttendance, StaffLeave, StaffProfile, User
from .services import AttendanceService, HolidayService, _is_late, holiday_summary

MODULE = "staff_attendance"


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


def _row(profile: StaffProfile, date) -> StaffAttendance | None:
    return StaffAttendance.objects.filter(staff_profile_id=profile.id, attendance_date=date).first()


def _assert_place(school: School, latitude, longitude, accuracy_m, radius: int) -> int:
    """The phone has to be within the radius of the school's pin. Returns
    how far it was, rounded to the metre."""
    if school.latitude is None or school.longitude is None:
        raise CheckInRefused(
            "NO_SCHOOL_LOCATION",
            "Your school has not set its location yet, so the app cannot check you in. Ask the office.",
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


def _assert_day(profile: StaffProfile, today, row: StaffAttendance | None) -> None:
    AttendanceService.assert_school_is_open(profile.school_id, today)

    if _approved_leave(profile, today) is not None or (row is not None and row.status == StaffAttendanceStatus.LEAVE):
        raise CheckInRefused("ON_LEAVE", "You are on leave today, so there is nothing to check in to.")


def _assert_enabled(school_id) -> None:
    if not modules.is_enabled(school_id, MODULE):
        raise ModuleDisabled(modules.get(MODULE).label)

    enabled, _ = _settings(school_id)

    if not enabled:
        raise CheckInRefused("CHECK_IN_OFF", "Your school marks staff attendance in the office, not from the app.")


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
        leave = _approved_leave(profile, today)
        row = _row(profile, today)

        check_in = working_hours.clock(row.check_in) if row and row.check_in else None
        check_out = working_hours.clock(row.check_out) if row and row.check_out else None
        late_after = Period.objects.filter(school_id=school_id).order_by("start_time").values_list("start_time", flat=True).first()

        reason = None
        if not enabled:
            reason = "Your school marks staff attendance in the office, not from the app."
        elif not is_open:
            reason = f"No attendance today: {holiday.name}." if holiday else "The school is closed today."
        elif leave is not None or (row is not None and row.status == StaffAttendanceStatus.LEAVE):
            reason = "You are on leave today."
        elif not has_pin:
            reason = "Your school has not set its location yet, so the app cannot check you in. Ask the office."

        return {
            "date": today.isoformat(),
            "now": now.strftime("%H:%M"),
            "enabled": enabled,
            "radius_m": radius,
            "school_day": {"is_open": is_open, "holiday": holiday_summary(holiday) if holiday else None},
            "on_leave": leave is not None or (row is not None and row.status == StaffAttendanceStatus.LEAVE),
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
        }

    @staticmethod
    def check_in(actor: User, latitude, longitude, accuracy_m=None) -> dict:
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

            if row is not None and row.check_in is not None:
                raise CheckInRefused(
                    "ALREADY_CHECKED_IN", f"You checked in at {working_hours.clock(row.check_in)} today."
                )

            distance = _assert_place(School.objects.get(pk=school_id), latitude, longitude, accuracy_m, radius)
            at = now.time().replace(second=0, microsecond=0)
            stamp = timezone.now()

            if row is None:
                row = StaffAttendance.objects.create(
                    school_id=school_id, staff_profile_id=profile.id, attendance_date=today,
                    status=StaffAttendanceStatus.PRESENT, check_in=at, marked_by_id=actor.id,
                    created_at=stamp, updated_at=stamp,
                )
                before = None
            else:
                # The office marked the day first - absent before they arrived,
                # or half a day. Being here, provably, makes an absent day a
                # present one; any other status the office chose stands.
                before = {"status": row.status, "check_in": None}
                if row.status == StaffAttendanceStatus.ABSENT:
                    row.status = StaffAttendanceStatus.PRESENT
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
    def check_out(actor: User, latitude, longitude, accuracy_m=None) -> dict:
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

            distance = _assert_place(School.objects.get(pk=school_id), latitude, longitude, accuracy_m, radius)
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

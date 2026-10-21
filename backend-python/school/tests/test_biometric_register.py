"""Punches reaching the staff register (docs/biometric.md, B3).

The earliest punch of a local day is the check-in and the latest is the
check-out. Everything here is about the edges of that one sentence, because
the sentence alone would let a device do things it must not:

- **A punch never creates a row.** Creating one means choosing a status, and
  a fingerprint reader cannot know whether somebody was late, on duty
  elsewhere, or simply there. A day nobody has marked stays unmarked.
- **A punch never clears a time.** A day with no punches is left exactly as
  it was, including the times a human typed.
- **One punch is an arrival, not a day.** A check-out equal to the check-in
  would read as a day of no work at all.
- **The clock is the school's.** The register is read at the school, and a
  half-hour offset is what catches an implementation that used the server's.

And the one that is about people: enrolling somebody reaches backwards into
days that were already marked while nobody knew whose punches those were.
"""

import datetime as dt
import io

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import StaffAttendanceStatus, UserRole
from django.utils import timezone

from school.models import AuditLog, Holiday, ModuleSetting, StaffAttendance

REGISTER = "/api/v1/staff-attendance/register"
UPLOAD = "/api/v1/biometric/punches/upload"


def _last_wednesday() -> dt.date:
    """A weekday in the last 30 days: the register refuses a weekend, and
    refuses anything older than a month."""
    today = dt.date.today()

    return today - dt.timedelta(days=(today.weekday() - 2) % 7 or 7)


A_SCHOOL_DAY = _last_wednesday()
ITS_DATE = A_SCHOOL_DAY.strftime("%m/%d/%Y")


class RegisterFromPunches(TestCase):
    def setUp(self):
        cache.clear()
        # Asia/Kolkata is +05:30. A 09:02 punch is 03:32 UTC, and a
        # half-hour offset is the one a naive implementation gets wrong.
        self.school = factories.SchoolFactory(name="Abbey Road School", timezone="Asia/Kolkata")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

        self.teacher = self.employee("EMP-1", biometric_user_id="17")
        self.other = self.employee("EMP-2", biometric_user_id="88")

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def employee(self, employee_id, biometric_user_id=None, school=None):
        where = school or self.school

        return factories.StaffProfileFactory(
            school=where,
            user=factories.UserFactory(school=where, role=UserRole.TEACHER),
            employee_id=employee_id,
            biometric_user_id=biometric_user_id,
        )

    def upload(self, lines, user=None, school=None):
        body = "\n".join(["biometric_user_id,punched_at", *lines]) + "\n"
        upload = io.BytesIO(body.encode("utf-8"))
        upload.name = "punches.csv"
        payload = {"file": upload}

        if school is not None:
            payload["school_id"] = school.id

        return self.as_user(user or self.admin).post(UPLOAD, payload, format="multipart")

    def mark(self, *profiles, status=StaffAttendanceStatus.PRESENT, **record):
        """Marks the day through the API the screen uses."""
        return self.client.post(
            "/api/v1/staff-attendance",
            {
                "school_id": self.school.id,
                "attendance_date": A_SCHOOL_DAY.isoformat(),
                "records": [
                    {"staff_profile_id": profile.id, "status": status, **record}
                    for profile in (profiles or (self.teacher,))
                ],
            },
            format="json",
        )

    def row(self, profile=None) -> StaffAttendance:
        return StaffAttendance.objects.get(
            staff_profile_id=(profile or self.teacher).id, attendance_date=A_SCHOOL_DAY
        )

    def screen(self):
        return self.client.get(f"{REGISTER}?school_id={self.school.id}&date={A_SCHOOL_DAY.isoformat()}")

    def whose(self, response, profile):
        return next(r for r in response.data["staff"] if r["staff_profile_id"] == profile.id)


class ADayAlreadyMarked(RegisterFromPunches):
    def test_the_first_and_last_punch_become_the_times(self):
        self.mark()

        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 13:10", f"17,{ITS_DATE} 17:31"])

        row = self.row()
        self.assertEqual(dt.time(9, 2), row.check_in)
        self.assertEqual(dt.time(17, 31), row.check_out)

    def test_the_status_a_human_set_is_untouched(self):
        self.mark(status=StaffAttendanceStatus.HALF_DAY)

        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertEqual(StaffAttendanceStatus.HALF_DAY, self.row().status)

    def test_a_later_punch_moves_the_check_out(self):
        """The case the plan names: the register was saved, and then somebody
        went home."""
        self.mark()
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.upload([f"17,{ITS_DATE} 18:40"])

        row = self.row()
        self.assertEqual(dt.time(9, 2), row.check_in)
        self.assertEqual(dt.time(18, 40), row.check_out)

    def test_one_punch_is_an_arrival_and_nothing_more(self):
        self.mark()

        self.upload([f"17,{ITS_DATE} 09:02"])

        row = self.row()
        self.assertEqual(dt.time(9, 2), row.check_in)
        self.assertIsNone(row.check_out)

    def test_a_single_punch_leaves_a_typed_check_out_alone(self):
        """Times are set from punches, never cleared by them."""
        self.mark(check_in="08:55", check_out="17:00")

        self.upload([f"17,{ITS_DATE} 09:02"])

        row = self.row()
        self.assertEqual(dt.time(9, 2), row.check_in)
        self.assertEqual(dt.time(17, 0), row.check_out)

    def test_a_day_with_no_punches_is_left_as_it_was(self):
        self.mark(check_in="08:55", check_out="17:00")

        self.upload([f"88,{ITS_DATE} 09:02", f"88,{ITS_DATE} 17:31"])

        row = self.row()
        self.assertEqual(dt.time(8, 55), row.check_in)
        self.assertEqual(dt.time(17, 0), row.check_out)

    def test_the_times_are_the_schools_wall_clock(self):
        """09:02 in Kolkata is 03:32 UTC. A register showing 03:32 would be
        the same bug the punch log was written to avoid."""
        self.mark()

        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertEqual(dt.time(9, 2), self.row().check_in)

    def test_the_upload_says_how_many_rows_it_filled(self):
        self.mark()

        response = self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertEqual(1, response.data["register_filled"])

    def test_it_is_audited_once_for_the_day(self):
        self.mark()

        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        entries = AuditLog.objects.filter(action="staff_attendance.times_from_device")
        self.assertEqual(1, entries.count())
        self.assertEqual([self.teacher.id], entries.get().new_values["staff_profile_ids"])


class ADayNobodyHasMarked(RegisterFromPunches):
    """B5: the punch marks it. Somebody touched the reader, so they were
    there - that is the one thing a punch is good evidence of."""

    def test_the_punch_marks_them_present(self):
        response = self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertEqual(StaffAttendanceStatus.PRESENT, self.row().status)
        self.assertEqual(1, response.data["register_marked"])

    def test_it_comes_with_the_times(self):
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        row = self.row()
        self.assertEqual(dt.time(9, 2), row.check_in)
        self.assertEqual(dt.time(17, 31), row.check_out)

    def test_nobody_is_named_as_having_marked_it(self):
        """A device did, and the register says so rather than putting
        somebody's name to a decision they did not make."""
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertIsNone(self.row().marked_by_id)

    def test_the_screen_says_it_was_the_device(self):
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertTrue(self.whose(self.screen(), self.teacher)["marked_by_device"])

    def test_somebody_with_no_punches_is_left_unmarked(self):
        """The absence of a punch is not evidence of absence: a broken
        reader, a failed scan and a file nobody uploaded all look like
        this."""
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertFalse(StaffAttendance.objects.filter(staff_profile_id=self.other.id).exists())
        self.assertIsNone(self.whose(self.screen(), self.other)["status"])

    def test_it_is_audited_as_a_marking(self):
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        entry = AuditLog.objects.get(action="staff_attendance.marked_by_device")
        self.assertEqual([self.teacher.id], entry.new_values["staff_profile_ids"])

    def test_a_human_who_marked_it_first_is_not_overruled(self):
        self.mark(status=StaffAttendanceStatus.LEAVE)

        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        row = self.row()
        self.assertEqual(StaffAttendanceStatus.LEAVE, row.status)
        self.assertEqual(dt.time(9, 2), row.check_in)
        self.assertFalse(self.whose(self.screen(), self.teacher)["marked_by_device"])


class ADayThePunchMayNotMark(RegisterFromPunches):
    """A holiday, a weekend, or a day older than the school lets anybody
    mark. The punch is kept either way; only the marking is refused."""

    def a_holiday(self):
        Holiday.objects.create(
            school_id=self.school.id,
            name="Founders Day",
            type="school_event",
            start_date=A_SCHOOL_DAY,
            end_date=A_SCHOOL_DAY,
        )

    def test_a_holiday_is_recorded_and_not_marked(self):
        self.a_holiday()

        response = self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertEqual(2, response.data["accepted"])
        self.assertEqual(0, response.data["register_marked"])
        self.assertEqual(0, StaffAttendance.objects.count())

    def test_a_day_the_school_does_not_run_is_recorded_and_not_marked(self):
        saturday = A_SCHOOL_DAY - dt.timedelta(days=4)
        its_date = saturday.strftime("%m/%d/%Y")

        response = self.upload([f"17,{its_date} 09:02", f"17,{its_date} 17:31"])

        self.assertEqual(2, response.data["accepted"])
        self.assertEqual(0, response.data["register_marked"])

    def test_history_older_than_the_schools_window_is_recorded_and_not_marked(self):
        """An upload of last year cannot rewrite attendance that humans are
        no longer allowed to touch either (docs/settings.md)."""
        ModuleSetting.objects.update_or_create(
            school_id=self.school.id,
            module="staff_attendance",
            defaults={"settings": {"max_backdate_days": 0}, "created_at": timezone.now(), "updated_at": timezone.now()},
        )

        response = self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertEqual(2, response.data["accepted"])
        self.assertEqual(0, response.data["register_marked"])

    def test_the_screen_still_pre_fills_the_times(self):
        """Nothing marked it, so the times are still worth showing to
        whoever opens the day."""
        self.a_holiday()
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        mine = self.whose(self.screen(), self.teacher)
        self.assertEqual("09:02", mine["check_in"])
        self.assertEqual("17:31", mine["check_out"])
        self.assertTrue(mine["times_from_device"])
        self.assertIsNone(mine["status"])


class WhetherSomebodyWasLate(RegisterFromPunches):
    """Derived from the timetable's first period, exactly as the staff
    report already computes it - and deliberately not a status, because
    four places count `status == PRESENT` and one of them is the day credit
    payroll reads."""

    def period_starting(self, at: dt.time):
        return factories.PeriodFactory(school=self.school, start_time=at, end_time=dt.time(at.hour + 1, 0))

    def test_arriving_after_the_first_period_is_late(self):
        self.period_starting(dt.time(9, 0))

        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertTrue(self.whose(self.screen(), self.teacher)["late"])

    def test_arriving_before_it_is_not(self):
        self.period_starting(dt.time(9, 0))

        self.upload([f"17,{ITS_DATE} 08:55", f"17,{ITS_DATE} 17:31"])

        self.assertFalse(self.whose(self.screen(), self.teacher)["late"])

    def test_a_school_with_no_timetable_has_nobody_late(self):
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertFalse(self.whose(self.screen(), self.teacher)["late"])

    def test_being_late_does_not_change_the_status(self):
        """The whole point of keeping it derived."""
        self.period_starting(dt.time(9, 0))

        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertEqual(StaffAttendanceStatus.PRESENT, self.row().status)


class PunchesNobodyOwns(RegisterFromPunches):
    def test_an_unmapped_id_reaches_no_register(self):
        self.mark()

        response = self.upload([f"99,{ITS_DATE} 09:02", f"99,{ITS_DATE} 17:31"])

        self.assertEqual(0, response.data["register_filled"])
        self.assertIsNone(self.row().check_in)

    def test_enrolling_somebody_fills_the_day_that_was_already_marked(self):
        """The whole reason punches are kept when nobody owns them: the fix
        for a missing enrolment must not be "upload the file again"."""
        waiting = self.employee("EMP-3")
        self.mark(waiting)
        self.upload([f"55,{ITS_DATE} 09:02", f"55,{ITS_DATE} 17:31"])

        self.assertIsNone(self.row(waiting).check_in)

        from school.services import StaffProfileService

        StaffProfileService.update(waiting, {"biometric_user_id": "55"})

        row = self.row(waiting)
        self.assertEqual(dt.time(9, 2), row.check_in)
        self.assertEqual(dt.time(17, 31), row.check_out)


class AnotherSchool(RegisterFromPunches):
    def test_its_punches_mark_its_own_register_and_not_this_one(self):
        """Same device id, different school. The id is only unique within
        one, so this is a real collision rather than a contrived one."""
        elsewhere = factories.SchoolFactory(name="Elsewhere High", timezone="Asia/Kolkata")
        theirs = self.employee("EMP-X", biometric_user_id="17", school=elsewhere)
        super_admin = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"], user=super_admin, school=elsewhere)

        self.assertFalse(StaffAttendance.objects.filter(staff_profile_id=self.teacher.id).exists())
        self.assertEqual(dt.time(9, 2), StaffAttendance.objects.get(staff_profile_id=theirs.id).check_in)

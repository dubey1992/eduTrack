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
from school.models import AuditLog, StaffAttendance

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
    def test_no_row_is_created(self):
        """Creating one would mean choosing a status."""
        response = self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        self.assertEqual(0, StaffAttendance.objects.count())
        self.assertEqual(0, response.data["register_filled"])

    def test_the_screen_pre_fills_the_times_instead(self):
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        mine = self.whose(self.screen(), self.teacher)
        self.assertEqual("09:02", mine["check_in"])
        self.assertEqual("17:31", mine["check_out"])
        self.assertEqual("8h 29m", mine["working_hours"])

    def test_the_screen_says_the_times_came_from_a_device(self):
        """So that whoever sets the status knows they did not type them."""
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        screen = self.screen()
        self.assertTrue(self.whose(screen, self.teacher)["times_from_device"])
        self.assertFalse(self.whose(screen, self.other)["times_from_device"])

    def test_the_status_stays_empty(self):
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])

        screen = self.screen()
        self.assertIsNone(self.whose(screen, self.teacher)["status"])
        self.assertFalse(screen.data["submitted"])

    def test_a_marked_row_is_no_longer_called_a_device_time(self):
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"])
        self.mark(check_in="08:55")

        self.assertFalse(self.whose(self.screen(), self.teacher)["times_from_device"])


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
    def test_its_punches_never_reach_this_register(self):
        """Same device id, different school. The id is only unique within
        one, so this is a real collision rather than a contrived one."""
        elsewhere = factories.SchoolFactory(name="Elsewhere High", timezone="Asia/Kolkata")
        theirs = self.employee("EMP-X", biometric_user_id="17", school=elsewhere)
        super_admin = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.mark()
        self.upload([f"17,{ITS_DATE} 09:02", f"17,{ITS_DATE} 17:31"], user=super_admin, school=elsewhere)

        self.assertIsNone(self.row().check_in)
        self.assertFalse(StaffAttendance.objects.filter(staff_profile_id=theirs.id).exists())

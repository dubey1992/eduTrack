"""Punches from the fingerprint devices (docs/biometric.md, B2).

A device reports an id it knows and a wall-clock time at the school. Four
rules carry the weight, and every one of them exists because of something a
device actually does:

- **An unmapped id is recorded, not dropped.** The first anybody should know
  of a missing enrolment is a row saying so, not a register with nothing in
  it.
- **The time has no zone.** It is wall clock at the school, so the school's
  own timezone turns it into an instant.
- **The same punch arrives more than once.** Devices resend and exports
  overlap; a repeat lands once and is counted, not refused.
- **A bad line does not throw away the file.** Unlike the bulk importer,
  whose all-or-nothing rule stops a half-finished import, a punch file is
  history - the readable rows are worth having.

And one that is about people rather than devices: enrolling somebody reaches
backwards, attaching the punches that arrived while nobody knew whose they
were.
"""

import datetime as dt
import io

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, punches, tokens
from school.enums import UserRole
from school.models import BiometricPunch

PUNCHES = "/api/v1/biometric/punches"
UPLOAD = f"{PUNCHES}/upload"


def a_file(lines: list[str], heading: str = "biometric_user_id,punched_at"):
    body = "\n".join([heading, *lines]) + "\n"
    upload = io.BytesIO(body.encode("utf-8"))
    upload.name = "punches.csv"

    return upload


class PunchTest(TestCase):
    def setUp(self):
        cache.clear()
        # Asia/Kolkata is +05:30: a 09:02 punch is 03:32 UTC, and a half-hour
        # offset is the one a naive implementation gets wrong.
        self.school = factories.SchoolFactory(name="Abbey Road School", timezone="Asia/Kolkata")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.other = factories.SchoolFactory(name="Elsewhere High")
        self.stranger = factories.UserFactory(school=self.other, role=UserRole.SCHOOL_ADMIN)

        # Readers on the wall: biometric arrives switched off, so a test
        # about it has to say the school asked for it (school/modules.py).
        factories.ModuleSettingFactory(school=self.school, module="biometric")
        factories.ModuleSettingFactory(school=self.other, module="biometric")

    def client_as(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def upload(self, lines, user=None, school=None, **extra):
        body = {"file": a_file(lines), **extra}
        actor = user or self.admin

        if actor.school_id is None and school is None:
            body["school_id"] = self.school.id
        elif school is not None:
            body["school_id"] = school.id

        return self.client_as(actor).post(UPLOAD, body, format="multipart")

    def enrol(self, biometric_user_id: str, employee_id: str = "EMP-1"):
        """Through the service the Add Employee screen uses, not the factory.

        The hook that attaches punches already in lives there, and a test
        that went round it would prove nothing about the real path.
        """
        from school.services import StaffProfileService

        return StaffProfileService.create_employee(
            {
                "school_id": self.school.id,
                "first_name": "Asha",
                "last_name": employee_id,
                "email": f"{employee_id.lower()}@example.invalid",
                "role": UserRole.TEACHER,
                "password": "Orchard7Lane",
            },
            {"employee_id": employee_id, "biometric_user_id": biometric_user_id, "joining_date": "2026-01-05"},
            self.admin,
        )


class Uploading(PunchTest):
    def test_a_punch_is_recorded(self):
        response = self.upload(["17,10/20/2026 09:02"])

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual((1, 0), (response.data["accepted"], response.data["duplicate"]))
        self.assertEqual(1, BiometricPunch.objects.count())

    def test_the_time_is_the_schools_wall_clock(self):
        """09:02 at a school in Asia/Kolkata is 03:32 UTC. A server that
        assumed its own zone would move every punch by five and a half
        hours."""
        self.upload(["17,10/20/2026 09:02"])

        punch = BiometricPunch.objects.get()

        self.assertEqual(dt.datetime(2026, 10, 20, 3, 32, tzinfo=dt.timezone.utc), punch.punched_at)
        self.assertEqual(dt.date(2026, 10, 20), punch.local_date)

    def test_a_punch_late_at_night_belongs_to_the_schools_day(self):
        """23:45 in Kolkata is 18:15 UTC the same day; the local date is the
        one the register is kept by, not the UTC one."""
        self.upload(["17,10/20/2026 23:45"])

        self.assertEqual(dt.date(2026, 10, 20), BiometricPunch.objects.get().local_date)

    def test_a_punch_early_in_the_morning_still_does(self):
        """04:00 in Kolkata is 22:30 UTC the *previous* day - the case that
        catches an implementation that took the date off the instant."""
        self.upload(["17,10/20/2026 04:00"])

        punch = BiometricPunch.objects.get()

        self.assertEqual(dt.date(2026, 10, 19), punch.punched_at.date())
        self.assertEqual(dt.date(2026, 10, 20), punch.local_date)

    def test_seconds_are_read_when_the_device_sends_them(self):
        self.upload(["17,10/20/2026 09:02:30"])

        self.assertEqual(30, BiometricPunch.objects.get().punched_at.second)

    def test_the_line_as_it_arrived_is_kept(self):
        # For when a time looks wrong and somebody has to work out whether we
        # or the device misread it.
        self.upload(["17,10/20/2026 09:02"])

        self.assertEqual("17,10/20/2026 09:02", BiometricPunch.objects.get().raw)


class AnIdNobodyHasMapped(PunchTest):
    def test_the_punch_is_still_recorded(self):
        # The whole point: a register with nothing in it is a worse way to
        # learn about a missing enrolment than a row saying so.
        self.upload(["99,10/20/2026 09:02"])

        punch = BiometricPunch.objects.get()

        self.assertEqual("99", punch.biometric_user_id)
        self.assertIsNone(punch.staff_profile_id)

    def test_a_mapped_id_is_attributed(self):
        profile = self.enrol("17")

        self.upload(["17,10/20/2026 09:02"])

        self.assertEqual(profile.id, BiometricPunch.objects.get().staff_profile_id)

    def test_another_schools_enrolment_is_not_borrowed(self):
        """Two schools number their own staff from 1; id 17 at one school is
        nobody at the other."""
        factories.StaffProfileFactory(school=self.other, employee_id="EMP-9", biometric_user_id="17")

        self.upload(["17,10/20/2026 09:02"])

        self.assertIsNone(BiometricPunch.objects.get().staff_profile_id)


class EnrollingReachesBackwards(PunchTest):
    """Punches that arrived before anybody said whose they were.

    Without this, enrolling somebody fixes only the future and those days'
    registers can only be put right by re-uploading the file.
    """

    def test_enrolling_attaches_the_punches_already_in(self):
        self.upload(["17,10/20/2026 09:02", "17,10/20/2026 17:10"])
        self.assertEqual(2, BiometricPunch.objects.filter(staff_profile__isnull=True).count())

        profile = self.enrol("17")

        self.assertEqual(2, BiometricPunch.objects.filter(staff_profile_id=profile.id).count())

    def test_it_leaves_other_peoples_punches_alone(self):
        self.upload(["17,10/20/2026 09:02", "18,10/20/2026 09:03"])

        profile = self.enrol("17")

        self.assertEqual(1, BiometricPunch.objects.filter(staff_profile_id=profile.id).count())
        self.assertEqual(1, BiometricPunch.objects.filter(staff_profile__isnull=True).count())

    def test_correcting_a_mistyped_id_lets_go_of_what_it_claimed(self):
        """An id typed in error must not leave somebody else's punches on
        this person's register - and those punches are still real, so they go
        back to unattached rather than being deleted."""
        profile = self.enrol("17")
        self.upload(["17,10/20/2026 09:02"])
        self.assertEqual(1, BiometricPunch.objects.filter(staff_profile_id=profile.id).count())

        from school.services import StaffProfileService

        StaffProfileService.update(profile, {"biometric_user_id": "18"})

        self.assertEqual(0, BiometricPunch.objects.filter(staff_profile_id=profile.id).count())
        self.assertEqual(1, BiometricPunch.objects.filter(staff_profile__isnull=True).count())

    def test_unenrolling_entirely_also_lets_go(self):
        profile = self.enrol("17")
        self.upload(["17,10/20/2026 09:02"])

        from school.services import StaffProfileService

        StaffProfileService.update(profile, {"biometric_user_id": None})

        self.assertEqual(1, BiometricPunch.objects.filter(staff_profile__isnull=True).count())


class TheSamePunchTwice(PunchTest):
    def test_a_repeat_lands_once(self):
        self.upload(["17,10/20/2026 09:02"])

        response = self.upload(["17,10/20/2026 09:02"])

        self.assertEqual((0, 1), (response.data["accepted"], response.data["duplicate"]))
        self.assertEqual(1, BiometricPunch.objects.count())

    def test_an_overlapping_export_keeps_what_is_new(self):
        """The common case: exports are by date range and people re-export a
        wider range than last time."""
        self.upload(["17,10/20/2026 09:02"])

        response = self.upload(["17,10/20/2026 09:02", "17,10/21/2026 09:04"])

        self.assertEqual((1, 1), (response.data["accepted"], response.data["duplicate"]))
        self.assertEqual(2, BiometricPunch.objects.count())

    def test_a_duplicate_inside_one_file_is_counted_too(self):
        response = self.upload(["17,10/20/2026 09:02", "17,10/20/2026 09:02"])

        self.assertEqual((1, 1), (response.data["accepted"], response.data["duplicate"]))

    def test_the_same_time_for_a_different_person_is_a_different_punch(self):
        response = self.upload(["17,10/20/2026 09:02", "18,10/20/2026 09:02"])

        self.assertEqual(2, response.data["accepted"])

    def test_two_schools_may_both_have_a_punch_at_that_moment(self):
        self.upload(["17,10/20/2026 09:02"])

        theirs = self.upload(["17,10/20/2026 09:02"], user=self.stranger)

        self.assertEqual(1, theirs.data["accepted"])


class ABadLine(PunchTest):
    def test_it_does_not_throw_away_the_file(self):
        # A month of attendance should not be refused because one row of it
        # is unreadable.
        response = self.upload(["17,10/20/2026 09:02", "18,nonsense", "19,10/20/2026 09:04"])

        self.assertEqual(2, response.data["accepted"])
        self.assertEqual(1, len(response.data["refused"]))

    def test_it_says_which_line(self):
        response = self.upload(["17,10/20/2026 09:02", "18,nonsense"])

        self.assertIn("Line 3", response.data["refused"][0])

    def test_every_bad_line_is_reported_not_just_the_first(self):
        response = self.upload(["18,nonsense", "19,also nonsense"])

        self.assertEqual(2, len(response.data["refused"]))

    def test_a_missing_id_is_a_bad_line(self):
        response = self.upload([",10/20/2026 09:02"])

        self.assertEqual(0, response.data["accepted"])
        self.assertIn("no biometric id", response.data["refused"][0])

    def test_the_wrong_columns_refuse_the_file(self):
        """Not a line problem: the file is the wrong file, and reading it row
        by row would silently import the wrong column."""
        upload = a_file(["17,10/20/2026 09:02"], heading="who,when")
        response = self.client_as(self.admin).post(UPLOAD, {"file": upload}, format="multipart")

        self.assertEqual(0, response.data["accepted"])
        self.assertIn("column headings", response.data["refused"][0])

    def test_an_empty_file_says_so(self):
        upload = io.BytesIO(b"")
        upload.name = "empty.csv"

        response = self.client_as(self.admin).post(UPLOAD, {"file": upload}, format="multipart")

        self.assertIn("empty", response.data["refused"][0])

    def test_no_file_at_all_is_a_validation_error(self):
        response = self.client_as(self.admin).post(UPLOAD, {}, format="multipart")

        self.assertEqual(422, response.status_code)
        self.assertIn("file", response.data["details"]["errors"])

    def test_a_blank_trailing_line_is_not_a_row(self):
        response = self.upload(["17,10/20/2026 09:02", "", "  "])

        self.assertEqual(1, response.data["accepted"])
        self.assertEqual([], response.data["refused"])


class ReadingTheLog(PunchTest):
    def setUp(self):
        super().setUp()
        self.profile = self.enrol("17", employee_id="EMP-7")
        self.upload(["17,10/20/2026 09:02", "99,10/20/2026 09:05", "17,10/21/2026 09:01"])

    def rows(self, user=None, **params):
        response = self.client_as(user or self.admin).get(PUNCHES, params)

        self.assertEqual(200, response.status_code, response.data)

        return response.data

    def test_it_lists_them_newest_first(self):
        data = self.rows()

        self.assertEqual(3, data["meta"]["total"])
        self.assertEqual("2026-10-21", data["data"][0]["local_date"])

    def test_an_attributed_punch_names_the_person(self):
        row = [r for r in self.rows()["data"] if r["biometric_user_id"] == "17"][0]

        self.assertEqual("EMP-7", row["employee_id"])
        self.assertIsNotNone(row["staff_name"])

    def test_an_unattributed_one_names_nobody_rather_than_guessing(self):
        row = [r for r in self.rows()["data"] if r["biometric_user_id"] == "99"][0]

        self.assertIsNone(row["staff_profile_id"])
        self.assertIsNone(row["staff_name"])

    def test_the_time_is_shown_on_the_schools_clock(self):
        row = [r for r in self.rows()["data"] if r["biometric_user_id"] == "99"][0]

        # 09:05 in Kolkata, not 03:35 UTC - the person reading this is at the
        # school.
        self.assertEqual("10/20/2026 9:05 AM", row["punched_at_label"])

    def test_the_unattributed_count_travels_with_the_page(self):
        """"None on this page" and "none at all" are different answers, and
        twenty rows cannot tell them apart."""
        self.assertEqual(1, self.rows()["unmatched_total"])

    def test_they_can_be_narrowed_to_the_unattributed(self):
        data = self.rows(unmatched="1")

        self.assertEqual(1, data["meta"]["total"])
        self.assertEqual("99", data["data"][0]["biometric_user_id"])

    def test_by_day(self):
        self.assertEqual(2, self.rows(date="2026-10-20")["meta"]["total"])

    def test_by_range(self):
        self.assertEqual(1, self.rows(**{"from": "2026-10-21"})["meta"]["total"])

    def test_by_who(self):
        self.assertEqual(2, self.rows(q="EMP-7")["meta"]["total"])

    def test_by_the_device_id_itself(self):
        self.assertEqual(1, self.rows(q="99")["meta"]["total"])


class WhoSeesWhat(PunchTest):
    def test_a_school_sees_only_its_own(self):
        self.upload(["17,10/20/2026 09:02"])
        self.upload(["17,10/20/2026 09:02"], user=self.stranger)

        rows = self.client_as(self.admin).get(PUNCHES).data

        self.assertEqual(1, rows["meta"]["total"])
        self.assertEqual(self.school.id, rows["data"][0]["school_id"])

    def test_a_teacher_may_not_upload(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(403, self.upload(["17,10/20/2026 09:02"], user=teacher).status_code)

    def test_an_admin_asking_for_another_school_is_filed_under_their_own(self):
        """Not a refusal, and deliberately: an actor who may write into one
        school writes into it whatever the request says, because the client's
        school_id is never trusted (CLAUDE.md rule 10). The punch lands - it
        just lands where it belongs."""
        response = self.upload(["17,10/20/2026 09:02"], school=self.other)

        self.assertEqual(200, response.status_code)
        self.assertEqual(0, BiometricPunch.objects.filter(school=self.other).count())
        self.assertEqual(1, BiometricPunch.objects.filter(school=self.school).count())


class ReadingAFileOnItsOwn(TestCase):
    """The parser, without a school or a request around it."""

    def test_both_time_shapes(self):
        rows, problems = punches.parse_csv(a_file(["17,10/20/2026 09:02", "18,10/20/2026 09:02:30"]))

        self.assertEqual([], problems)
        self.assertEqual(2, len(rows))

    def test_the_times_come_back_naive(self):
        # The zone belongs to the school, not to the file.
        rows, _ = punches.parse_csv(a_file(["17,10/20/2026 09:02"]))

        self.assertIsNone(rows[0]["punched_at"].tzinfo)

    def test_a_date_that_is_not_a_date(self):
        _, problems = punches.parse_csv(a_file(["17,10/40/2026 09:02"]))

        self.assertEqual(1, len(problems))

    def test_an_id_too_long_for_the_column(self):
        _, problems = punches.parse_csv(a_file([("9" * 33) + ",10/20/2026 09:02"]))

        self.assertIn("too long", problems[0])

    def test_a_file_of_a_whole_year_is_refused_politely(self):
        lines = [f"17,10/20/2026 09:{minute:02d}" for minute in range(60)] * 40

        rows, problems = punches.parse_csv(a_file(lines))

        self.assertEqual(punches.MAX_PUNCHES, len(rows))
        self.assertIn("split the file", problems[0])

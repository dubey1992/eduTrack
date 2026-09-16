"""The daily register, over HTTP.

Most of the risk here is about a *day* rather than a student.

**A register can only be taken for a day the school ran.** A holiday names
itself in the refusal and a weekend is refused too, because every working-day
figure in the product excludes both - a Saturday register that no percentage
counts is worse than none.

**Submitting is not correcting.** A first submission for a class and day is
refused if one already exists, so a duplicate tap cannot silently overwrite a
different set of marks.

And marking alerts guardians - but only for a mark that actually changed, and
only through the queue.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import AttendanceAlertMode, AttendanceStatus, MessageEvent, UserRole
from school.models import Attendance, CommunicationSetting, Message, QueuedJob

# A Wednesday, comfortably in the past. Fixed rather than derived from today,
# so the suite does not start failing on a Saturday.
A_SCHOOL_DAY = dt.date(2026, 9, 9)
A_SATURDAY = dt.date(2026, 9, 12)


class AttendanceTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")
        self.year = factories.AcademicYearFactory(school=self.school, is_current=True)
        self.school_class = factories.SchoolClassFactory(
            academic_year=self.year, school=self.school, name="Grade 8"
        )
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

        self.students = [
            factories.StudentFactory(
                school=self.school,
                class_section=self.section,
                admission_number=f"ADM-{index}",
                first_name=f"Student{index}",
                guardian_mobile="+91 9000000000",
            )
            for index in range(2)
        ]

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def marks(self, status=AttendanceStatus.PRESENT, **overrides) -> dict:
        body = {
            "class_section_id": self.section.id,
            "attendance_date": A_SCHOOL_DAY.isoformat(),
            "records": [
                {"student_id": student.id, "status": status} for student in self.students
            ],
        }
        body.update(overrides)

        return body


class TheRegisterScreen(AttendanceTest):
    def test_it_lists_the_active_roster_with_no_marks_yet(self):
        response = self.client.get(
            f"/api/v1/attendance/register?class_section_id={self.section.id}"
            f"&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertFalse(response.data["submitted"])
        self.assertIsNone(response.data["holiday"])
        self.assertEqual(2, len(response.data["students"]))
        self.assertIsNone(response.data["students"][0]["status"])

    def test_an_inactive_student_is_not_on_it(self):
        gone = self.students[0]
        gone.status = "inactive"
        gone.save()

        response = self.client.get(
            f"/api/v1/attendance/register?class_section_id={self.section.id}"
            f"&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual(
            [self.students[1].id], [s["student_id"] for s in response.data["students"]]
        )

    def test_it_shows_the_marks_once_the_day_is_submitted(self):
        self.client.post("/api/v1/attendance", self.marks(), format="json")

        response = self.client.get(
            f"/api/v1/attendance/register?class_section_id={self.section.id}"
            f"&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertTrue(response.data["submitted"])
        self.assertEqual(
            ["present", "present"], [s["status"] for s in response.data["students"]]
        )

    def test_it_names_the_holiday_rather_than_leaving_the_screen_to_guess(self):
        factories_holiday(self.school, A_SCHOOL_DAY, "Diwali")

        response = self.client.get(
            f"/api/v1/attendance/register?class_section_id={self.section.id}"
            f"&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual("Diwali", response.data["holiday"]["name"])

    def test_a_section_that_does_not_exist_is_422_not_403(self):
        # A 403 about a section that does not exist would tell the caller it
        # does.
        response = self.client.get(
            f"/api/v1/attendance/register?class_section_id=999999&date={A_SCHOOL_DAY.isoformat()}"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("class_section_id", response.data["details"]["errors"])


class SubmittingADay(AttendanceTest):
    def test_a_register_is_submitted(self):
        response = self.client.post("/api/v1/attendance", self.marks(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertTrue(response.data["submitted"])
        self.assertEqual(2, Attendance.objects.count())

    def test_the_school_and_year_come_from_the_section_not_the_request(self):
        self.client.post(
            "/api/v1/attendance",
            self.marks(school_id=factories.SchoolFactory().id),
            format="json",
        )

        mark = Attendance.objects.first()
        self.assertEqual(self.school.id, mark.school_id)
        self.assertEqual(self.year.id, mark.academic_year_id)

    def test_submitting_twice_is_refused_rather_than_overwriting(self):
        # A duplicate tap must not silently replace a different set of marks.
        self.client.post("/api/v1/attendance", self.marks(), format="json")

        response = self.client.post(
            "/api/v1/attendance", self.marks(AttendanceStatus.ABSENT), format="json"
        )

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ATTENDANCE_ALREADY_SUBMITTED", response.data["code"])
        self.assertEqual(
            ["present", "present"],
            list(Attendance.objects.values_list("status", flat=True)),
        )

    def test_correcting_a_day_is_its_own_action_and_is_allowed(self):
        self.client.post("/api/v1/attendance", self.marks(), format="json")

        response = self.client.patch(
            "/api/v1/attendance", self.marks(AttendanceStatus.ABSENT), format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(
            ["absent", "absent"], [s["status"] for s in response.data["students"]]
        )

    def test_a_student_from_another_section_cannot_be_marked(self):
        # A mark against somebody else's student is a row nobody's register
        # shows and every percentage counts.
        elsewhere = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        outsider = factories.StudentFactory(
            school=self.school, class_section=elsewhere, admission_number="ADM-X"
        )

        response = self.client.post(
            "/api/v1/attendance",
            self.marks(records=[{"student_id": outsider.id, "status": "present"}]),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("records", response.data["details"]["errors"])

    def test_the_same_student_twice_is_refused(self):
        response = self.client.post(
            "/api/v1/attendance",
            self.marks(
                records=[
                    {"student_id": self.students[0].id, "status": "present"},
                    {"student_id": self.students[0].id, "status": "absent"},
                ]
            ),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn(
            "Each student can only appear once in the attendance records.",
            response.data["details"]["errors"]["records"],
        )

    def test_a_status_that_does_not_exist_is_refused(self):
        response = self.client.post(
            "/api/v1/attendance",
            self.marks(records=[{"student_id": self.students[0].id, "status": "maybe"}]),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)

    def test_an_empty_register_is_refused(self):
        response = self.client.post("/api/v1/attendance", self.marks(records=[]), format="json")

        self.assertEqual(422, response.status_code, response.data)


class OnlyOnADayTheSchoolRan(AttendanceTest):
    def test_a_holiday_is_refused_and_names_itself(self):
        factories_holiday(self.school, A_SCHOOL_DAY, "Diwali")

        response = self.client.post("/api/v1/attendance", self.marks(), format="json")

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("ATTENDANCE_ON_HOLIDAY", response.data["code"])
        self.assertEqual(
            "Attendance cannot be marked on Diwali - it is a holiday.",
            response.data["message"],
        )
        self.assertEqual(0, Attendance.objects.count())

    def test_a_weekend_is_refused_too(self):
        # Every working-day figure excludes it, so a Saturday register that no
        # percentage counts is worse than none.
        response = self.client.post(
            "/api/v1/attendance",
            self.marks(attendance_date=A_SATURDAY.isoformat()),
            format="json",
        )

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("NON_WORKING_DAY", response.data["code"])

    def test_correcting_a_day_is_checked_the_same_way(self):
        # Otherwise a holiday declared after the fact could be worked around
        # by editing rather than submitting.
        self.client.post("/api/v1/attendance", self.marks(), format="json")
        factories_holiday(self.school, A_SCHOOL_DAY, "Declared later")

        response = self.client.patch(
            "/api/v1/attendance", self.marks(AttendanceStatus.ABSENT), format="json"
        )

        self.assertEqual(409, response.status_code, response.data)

    def test_a_future_date_is_refused_against_the_schools_calendar(self):
        # Not the server's. A teacher in Asia/Kolkata at 7am is ahead of UTC,
        # and the server would otherwise call an ordinary morning the future.
        tomorrow = dt.date.today() + dt.timedelta(days=2)

        response = self.client.post(
            "/api/v1/attendance",
            self.marks(attendance_date=tomorrow.isoformat()),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("attendance_date", response.data["details"]["errors"])


class TellingTheGuardians(AttendanceTest):
    def queued(self):
        return QueuedJob.objects.filter(name="send_message")

    def test_an_absence_alerts_the_guardian(self):
        self.client.post(
            "/api/v1/attendance", self.marks(AttendanceStatus.ABSENT), format="json"
        )

        self.assertEqual(2, Message.objects.count())
        self.assertEqual(2, self.queued().count(), "queued, never sent in the request")
        self.assertIn("was marked ABSENT", Message.objects.first().body)

    def test_a_present_mark_does_not_by_default(self):
        # A text every morning saying a child turned up is one every parent
        # learns to ignore.
        self.client.post("/api/v1/attendance", self.marks(), format="json")

        self.assertEqual(0, Message.objects.count())

    def test_a_school_can_ask_for_both(self):
        CommunicationSetting.objects.create(
            school_id=self.school.id,
            sms_enabled=True,
            attendance_alerts=AttendanceAlertMode.PRESENT_AND_ABSENT,
            transport_alerts_enabled=True,
            leave_alerts_enabled=True,
            provider="log",
        )

        self.client.post("/api/v1/attendance", self.marks(), format="json")

        self.assertEqual(2, Message.objects.count())

    def test_correcting_a_remark_does_not_text_a_parent_twice(self):
        # Only a new mark or a changed one alerts.
        self.client.post(
            "/api/v1/attendance", self.marks(AttendanceStatus.ABSENT), format="json"
        )
        Message.objects.all().delete()
        self.queued().delete()

        self.client.patch(
            "/api/v1/attendance",
            self.marks(
                records=[
                    {"student_id": s.id, "status": "absent", "remarks": "Called home"}
                    for s in self.students
                ]
            ),
            format="json",
        )

        self.assertEqual(0, Message.objects.count())

    def test_changing_a_mark_does_alert(self):
        self.client.post("/api/v1/attendance", self.marks(), format="json")
        Message.objects.all().delete()

        self.client.patch(
            "/api/v1/attendance", self.marks(AttendanceStatus.ABSENT), format="json"
        )

        self.assertEqual(2, Message.objects.count())
        self.assertEqual(
            MessageEvent.ATTENDANCE_ABSENT, Message.objects.first().event
        )

    def test_a_student_marked_leave_is_not_news_to_anybody(self):
        self.client.post(
            "/api/v1/attendance", self.marks(AttendanceStatus.LEAVE), format="json"
        )

        self.assertEqual(0, Message.objects.count())


class WhoMayMarkIt(AttendanceTest):
    def test_the_class_teacher_may_read_and_mark_their_own_section(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.section.class_teacher_id = teacher.id
        self.section.save()

        client = self.as_user(teacher)

        self.assertEqual(
            200,
            client.get(
                f"/api/v1/attendance/register?class_section_id={self.section.id}"
                f"&date={A_SCHOOL_DAY.isoformat()}"
            ).status_code,
        )
        self.assertEqual(
            201, client.post("/api/v1/attendance", self.marks(), format="json").status_code
        )

    def test_a_teacher_of_another_section_may_do_neither(self):
        # "A Teacher assigned to 8A must not access 9A" - the most specific
        # authorization rule in the product.
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        other = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        other.class_teacher_id = teacher.id
        other.save()

        client = self.as_user(teacher)

        self.assertEqual(
            403,
            client.get(
                f"/api/v1/attendance/register?class_section_id={self.section.id}"
                f"&date={A_SCHOOL_DAY.isoformat()}"
            ).status_code,
        )
        self.assertEqual(
            403, client.post("/api/v1/attendance", self.marks(), format="json").status_code
        )

    def test_an_admin_from_another_school_may_do_neither(self):
        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual(
            403, outsider.post("/api/v1/attendance", self.marks(), format="json").status_code
        )

    def test_a_teacher_only_sees_their_own_sections_in_the_list(self):
        self.client.post("/api/v1/attendance", self.marks(), format="json")

        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        response = self.as_user(teacher).get("/api/v1/attendance?per_page=100")

        self.assertEqual([], response.data["data"])

    def test_the_list_never_includes_another_schools_marks(self):
        self.client.post("/api/v1/attendance", self.marks(), format="json")

        outsider = self.as_user(
            factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)
        )

        response = outsider.get("/api/v1/attendance?per_page=100")

        self.assertEqual([], response.data["data"])

    def test_a_role_with_no_attendance_access_is_refused(self):
        for role in (UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role):
                client = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, client.get("/api/v1/attendance").status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/attendance").status_code)


class TheList(AttendanceTest):
    def setUp(self):
        super().setUp()
        self.client.post("/api/v1/attendance", self.marks(), format="json")

    def test_a_mark_comes_back_whole(self):
        row = self.client.get("/api/v1/attendance").data["data"][0]

        for field in (
            "id", "school_id", "academic_year_id", "class_section_id", "class_section_name",
            "student_id", "student_name", "attendance_date", "status", "remarks",
            "marked_by", "marked_by_name",
        ):
            self.assertIn(field, row)

        self.assertEqual("Grade 8 A", row["class_section_name"])
        self.assertEqual(self.admin.name, row["marked_by_name"])

    def test_it_filters_by_student_and_by_date_range(self):
        by_student = self.client.get(f"/api/v1/attendance?student_id={self.students[0].id}")
        outside = self.client.get("/api/v1/attendance?date_from=2027-01-01")

        self.assertEqual(1, by_student.data["meta"]["total"])
        self.assertEqual(0, outside.data["meta"]["total"])


def factories_holiday(school, date, name):
    from django.utils.timezone import now

    from school.models import Holiday

    return Holiday.objects.create(
        school_id=school.id,
        name=name,
        type="religious",
        start_date=date,
        end_date=date,
        created_at=now(),
        updated_at=now(),
    )

"""Daily teaching reports, over HTTP.

Three rules carry this module:

**Only the teacher of a period reports on it.** Being a teacher is not enough -
it has to be their period, and a school admin who teaches nothing files
nothing. Ownership is a 403, not a 422.

**A report belongs to a day the period ran.** The date must fall on the
period's weekday, not in the future on the *school's* calendar, and not on a
holiday or a weekend - nothing was taught, so there is nothing to report.

**Nobody reviews their own report**, whatever their role. An HOD teaches in the
department they head, so without a check they would pass the department test.
"""

import datetime as dt

from unittest import mock

from django.core.cache import cache
from django.db import connection
from django.test.utils import CaptureQueriesContext
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.services import SyllabusProgressService
from school.models import AuditLog, DailyTeachingReport, Holiday, SyllabusTopicProgress

# A Monday already in the past, so "not in the future" never interferes with
# the rule a test is actually about.
A_MONDAY = dt.date(2026, 9, 14)
A_TUESDAY = dt.date(2026, 9, 15)
A_SATURDAY = dt.date(2026, 9, 12)


class TeachingReportCase(TestCase):
    """The school, people and periods every report test starts from."""

    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(timezone="Asia/Kolkata")
        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.arts = factories.DepartmentFactory(school=self.school, name="Arts")

        self.hod = factories.UserFactory(school=self.school, role=UserRole.HOD)
        self.science.hod_user = self.hod
        self.science.save()
        self.employee(self.hod, self.science)

        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.employee(self.teacher, self.science)

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

        self.section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(
                school=self.school,
                academic_year=factories.AcademicYearFactory(school=self.school),
                name="Grade 8",
            ),
            name="A",
        )
        self.subject = factories.SubjectFactory(school=self.school, department=self.science)
        self.first = factories.PeriodFactory(school=self.school, period_number=1)
        self.second = factories.PeriodFactory(school=self.school, period_number=2)

        self.entry = self.period_for(self.teacher, self.first)

    # -- helpers ------------------------------------------------------------

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def employee(self, user, department):
        return factories.StaffProfileFactory(school=user.school, user=user, department=department)

    def period_for(self, teacher, period, day="monday"):
        return factories.TimetableEntryFactory(
            school=self.school,
            class_section=self.section,
            period=period,
            day_of_week=day,
            subject=self.subject,
            teacher=teacher,
        )

    def payload(self, **overrides) -> dict:
        body = {
            "timetable_entry_id": self.entry.id,
            "report_date": A_MONDAY.isoformat(),
            "topic_taught": "Linear equations",
        }
        body.update(overrides)

        return body

    def file(self, user=None, **overrides):
        return self.as_user(user or self.teacher).post(
            "/api/v1/teaching-reports", self.payload(**overrides), format="json"
        )

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]


class TeachingReportTest(TeachingReportCase):
    # -- filing -------------------------------------------------------------

    def test_a_teacher_files_a_report_for_their_own_period(self):
        response = self.file(homework="Exercise 4.2")

        self.assertEqual(201, response.status_code)
        self.assertEqual("Grade 8 A", response.data["class_section_name"])
        self.assertEqual(1, response.data["period_number"])
        self.assertEqual(self.teacher.name, response.data["teacher_name"])
        self.assertEqual("Exercise 4.2", response.data["homework"])
        self.assertIsNone(response.data["reviewed_at"])

    def test_an_hod_files_for_a_period_they_teach(self):
        entry = self.period_for(self.hod, self.second)

        response = self.file(self.hod, timetable_entry_id=entry.id)

        self.assertEqual(201, response.status_code)

    def test_a_teacher_cannot_file_for_somebody_elses_period(self):
        colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        entry = self.period_for(colleague, self.second)

        self.assertEqual(403, self.file(timetable_entry_id=entry.id).status_code)

    def test_a_school_admin_files_nothing(self):
        self.assertEqual(403, self.file(self.admin).status_code)

    def test_a_staff_account_files_nothing(self):
        staff = factories.UserFactory(school=self.school, role=UserRole.STAFF)

        self.assertEqual(403, self.file(staff).status_code)

    def test_the_date_must_be_the_periods_weekday(self):
        response = self.file(report_date=A_TUESDAY.isoformat())

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["The report date must fall on the day this period is scheduled (Monday)."],
            self.errors(response)["report_date"],
        )

    def test_a_future_date_is_refused(self):
        next_week = dt.date.today() + dt.timedelta(days=14)
        next_monday = next_week - dt.timedelta(days=next_week.weekday())

        response = self.file(report_date=next_monday.isoformat())

        self.assertEqual(422, response.status_code)
        self.assertIn("before or equal to", self.errors(response)["report_date"][0])

    def test_a_future_date_on_the_wrong_weekday_names_both_problems(self):
        # Laravel lists every failing rule on a field; a port that stopped at
        # the first would quietly tell the teacher half of what is wrong.
        next_week = dt.date.today() + dt.timedelta(days=14)
        next_tuesday = next_week - dt.timedelta(days=next_week.weekday()) + dt.timedelta(days=1)

        response = self.file(report_date=next_tuesday.isoformat())

        self.assertEqual(2, len(self.errors(response)["report_date"]))

    def test_a_date_problem_is_reported_alongside_a_missing_topic(self):
        response = self.file(report_date=A_TUESDAY.isoformat(), topic_taught="")

        self.assertEqual({"report_date", "topic_taught"}, set(self.errors(response)))

    def test_a_second_report_for_the_same_period_and_day_is_refused(self):
        self.file()

        response = self.file()

        self.assertEqual(409, response.status_code)
        self.assertEqual("TEACHING_REPORT_ALREADY_SUBMITTED", response.data["code"])

    def test_nothing_is_reported_on_a_holiday(self):
        Holiday.objects.create(
            school_id=self.school.id,
            name="Founders Day",
            type="school_event",
            start_date=A_MONDAY,
            end_date=A_MONDAY,
        )

        response = self.file()

        self.assertEqual(409, response.status_code)
        self.assertEqual("TEACHING_REPORT_ON_HOLIDAY", response.data["code"])
        self.assertIn("Founders Day", response.data["message"])

    def test_nothing_is_reported_at_the_weekend(self):
        entry = self.period_for(self.teacher, self.second, day="saturday")

        response = self.file(timetable_entry_id=entry.id, report_date=A_SATURDAY.isoformat())

        self.assertEqual(409, response.status_code)
        self.assertEqual("NON_WORKING_DAY", response.data["code"])

    def test_a_topic_is_required(self):
        response = self.file(topic_taught="")

        self.assertEqual(422, response.status_code)
        self.assertIn("topic_taught", self.errors(response))

    def test_a_period_that_is_not_there_is_invalid(self):
        response = self.file(timetable_entry_id=999999)

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["The selected timetable entry id is invalid."],
            self.errors(response)["timetable_entry_id"],
        )

    def test_homework_and_remarks_past_the_column_are_refused(self):
        response = self.file(homework="x" * 501, remarks="x" * 501)

        self.assertEqual({"homework", "remarks"}, set(self.errors(response)))

    # -- reviewing ----------------------------------------------------------

    def review(self, user, report):
        return self.as_user(user).patch(
            f"/api/v1/teaching-reports/{report.id}/review", {}, format="json"
        )

    def test_an_hod_reviews_their_departments_report(self):
        report = factories.DailyTeachingReportFactory(timetable_entry=self.entry)

        response = self.review(self.hod, report)

        self.assertEqual(200, response.status_code)
        self.assertEqual(self.hod.name, response.data["reviewed_by_name"])
        self.assertIsNotNone(response.data["reviewed_at"])

    def test_a_school_admin_reviews_any_report_in_their_school(self):
        report = factories.DailyTeachingReportFactory(timetable_entry=self.entry)

        self.assertEqual(200, self.review(self.admin, report).status_code)

    def test_a_super_admin_reviews_anywhere(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        report = factories.DailyTeachingReportFactory(timetable_entry=self.entry)

        self.assertEqual(200, self.review(root, report).status_code)

    def test_a_teacher_cannot_review_their_own_report(self):
        report = factories.DailyTeachingReportFactory(timetable_entry=self.entry)

        self.assertEqual(403, self.review(self.teacher, report).status_code)

    def test_an_hod_cannot_review_their_own_report(self):
        report = factories.DailyTeachingReportFactory(
            timetable_entry=self.period_for(self.hod, self.second)
        )

        self.assertEqual(403, self.review(self.hod, report).status_code)

    def test_a_teacher_cannot_review_a_colleagues_report(self):
        colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        report = factories.DailyTeachingReportFactory(timetable_entry=self.entry)

        self.assertEqual(403, self.review(colleague, report).status_code)

    def test_an_hod_cannot_review_another_departments_report(self):
        outsider = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.employee(outsider, self.arts)
        report = factories.DailyTeachingReportFactory(
            timetable_entry=self.period_for(outsider, self.second)
        )

        self.assertEqual(403, self.review(self.hod, report).status_code)

    def test_a_school_admin_cannot_review_another_schools_report(self):
        stranger = factories.UserFactory(
            school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN
        )
        report = factories.DailyTeachingReportFactory(timetable_entry=self.entry)

        self.assertEqual(403, self.review(stranger, report).status_code)

    def test_a_report_is_reviewed_once(self):
        report = factories.DailyTeachingReportFactory(
            timetable_entry=self.entry, reviewed_by=self.admin
        )

        response = self.review(self.hod, report)

        self.assertEqual(409, response.status_code)
        self.assertEqual("TEACHING_REPORT_ALREADY_REVIEWED", response.data["code"])

    def test_a_report_that_is_not_there_is_a_404(self):
        response = self.as_user(self.admin).patch(
            "/api/v1/teaching-reports/999999/review", {}, format="json"
        )

        self.assertEqual(404, response.status_code)

    # -- the list -----------------------------------------------------------

    def test_a_teacher_sees_only_their_own_reports(self):
        factories.DailyTeachingReportFactory(timetable_entry=self.entry)
        factories.DailyTeachingReportFactory(
            timetable_entry=self.period_for(self.hod, self.second)
        )

        response = self.as_user(self.teacher).get("/api/v1/teaching-reports")

        self.assertEqual(1, len(response.data["data"]))
        self.assertEqual(self.teacher.id, response.data["data"][0]["teacher_id"])

    def test_an_hod_sees_their_whole_department(self):
        factories.DailyTeachingReportFactory(timetable_entry=self.entry)
        outsider = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.employee(outsider, self.arts)
        factories.DailyTeachingReportFactory(
            timetable_entry=self.period_for(outsider, self.second)
        )

        response = self.as_user(self.hod).get("/api/v1/teaching-reports")

        self.assertEqual(1, len(response.data["data"]))

    def test_a_school_admin_sees_only_their_own_school(self):
        factories.DailyTeachingReportFactory(timetable_entry=self.entry)
        factories.DailyTeachingReportFactory()

        response = self.as_user(self.admin).get("/api/v1/teaching-reports")

        self.assertEqual(1, len(response.data["data"]))

    def test_staff_and_transport_managers_do_not_browse_reports(self):
        for role in (UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            user = factories.UserFactory(school=self.school, role=role)

            self.assertEqual(
                403, self.as_user(user).get("/api/v1/teaching-reports").status_code, role
            )

    def test_one_teachers_reports_for_one_day_page_without_repeats(self):
        # One report per period, so a teacher and a date tie on every row of
        # a busy day. The id is what keeps paging honest.
        for number in range(3, 9):
            factories.DailyTeachingReportFactory(
                timetable_entry=self.period_for(
                    self.teacher, factories.PeriodFactory(school=self.school, period_number=number)
                )
            )

        seen = [
            self.as_user(self.admin)
            .get(f"/api/v1/teaching-reports?per_page=1&page={page}")
            .data["data"][0]["id"]
            for page in range(1, 7)
        ]

        self.assertEqual(6, len(set(seen)))

    # -- the KPI row --------------------------------------------------------

    def test_the_summary_counts_scheduled_submitted_and_pending(self):
        self.period_for(self.hod, self.second)
        factories.DailyTeachingReportFactory(timetable_entry=self.entry)

        response = self.as_user(self.admin).get(
            f"/api/v1/teaching-reports/summary?date={A_MONDAY.isoformat()}"
        )

        self.assertEqual(
            {"scheduled": 2, "submitted": 1, "pending": 1, "holiday": None}, response.data
        )

    def test_a_teachers_summary_counts_only_their_own_periods(self):
        self.period_for(self.hod, self.second)

        response = self.as_user(self.teacher).get(
            f"/api/v1/teaching-reports/summary?date={A_MONDAY.isoformat()}"
        )

        self.assertEqual(1, response.data["scheduled"])

    def test_on_a_holiday_nothing_is_scheduled_and_the_holiday_is_named(self):
        Holiday.objects.create(
            school_id=self.school.id,
            name="Founders Day",
            type="school_event",
            start_date=A_MONDAY,
            end_date=A_MONDAY,
        )

        response = self.as_user(self.admin).get(
            f"/api/v1/teaching-reports/summary?date={A_MONDAY.isoformat()}"
        )

        self.assertEqual(0, response.data["scheduled"])
        self.assertEqual("Founders Day", response.data["holiday"])

    def test_the_summary_needs_a_date(self):
        response = self.as_user(self.admin).get("/api/v1/teaching-reports/summary")

        self.assertEqual(422, response.status_code)
        self.assertIn("date", self.errors(response))

    def test_the_summary_is_refused_before_the_date_is_read(self):
        staff = factories.UserFactory(school=self.school, role=UserRole.STAFF)

        response = self.as_user(staff).get("/api/v1/teaching-reports/summary")

        self.assertEqual(403, response.status_code)

    def test_a_report_carries_nothing_extra(self):
        response = self.file()

        self.assertEqual(
            {
                "id", "school_id", "timetable_entry_id", "class_section_name",
                "period_number", "subject_name", "teacher_id", "teacher_name",
                "report_date", "topic_taught", "syllabus_topic_id", "syllabus_topic_name",
                "homework", "remarks", "reviewed_by", "reviewed_by_name", "reviewed_at",
            },
            set(response.data),
        )
        self.assertEqual(1, DailyTeachingReport.objects.count())


class FilingTicksTheSyllabus(TeachingReportTest):
    """One entry instead of two (docs/insights.md, slice 3).

    A teacher used to write the topic in the daily report and then tick the
    same topic on the Syllabus screen. Filing now does both - which puts a
    write on a path that only ever read before, so most of what is pinned
    here is what it must *not* do.
    """

    def setUp(self):
        super().setUp()
        self.topic = factories.SyllabusTopicFactory(
            subject=self.subject, school=self.school, title="Linear equations", sequence_number=1
        )

    def covered(self, topic=None, section=None) -> bool:
        return SyllabusTopicProgress.objects.filter(
            syllabus_topic_id=(topic or self.topic).id,
            class_section_id=(section or self.section).id,
        ).exists()

    def test_filing_a_report_that_names_a_topic_marks_it_covered(self):
        response = self.file(syllabus_topic_id=self.topic.id)

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.topic.id, response.data["syllabus_topic_id"])
        self.assertEqual("Linear equations", response.data["syllabus_topic_name"])
        self.assertTrue(self.covered(), "the syllabus should not need ticking a second time")

    def test_the_mark_records_who_taught_it(self):
        self.file(syllabus_topic_id=self.topic.id)

        progress = SyllabusTopicProgress.objects.get(syllabus_topic_id=self.topic.id)

        self.assertEqual(self.teacher.id, progress.completed_by_id)
        self.assertEqual(self.school.id, progress.school_id)

    def test_a_report_naming_no_topic_ticks_nothing(self):
        """A revision period, a test or a visiting speaker is a real lesson
        and names no chapter."""
        response = self.file()

        self.assertEqual(201, response.status_code)
        self.assertIsNone(response.data["syllabus_topic_id"])
        self.assertFalse(SyllabusTopicProgress.objects.exists())

    def test_topic_taught_still_says_what_happened(self):
        """The text is not replaced by the foreign key: a year of existing
        reports have only the text, and a lesson is often not a chapter."""
        response = self.file(topic_taught="Revision before the test")

        self.assertEqual("Revision before the test", response.data["topic_taught"])

    def test_a_topic_already_covered_keeps_the_record_of_who_did_it_first(self):
        other = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        SyllabusProgressService.toggle(self.topic, self.section, True, other)
        before = SyllabusTopicProgress.objects.get(syllabus_topic_id=self.topic.id)

        self.file(syllabus_topic_id=self.topic.id)

        after = SyllabusTopicProgress.objects.get(syllabus_topic_id=self.topic.id)
        self.assertEqual(before.completed_by_id, after.completed_by_id, "teaching it again is not covering it again")
        self.assertEqual(before.completed_at, after.completed_at)

    def test_two_reports_on_the_same_topic_leave_one_mark(self):
        self.file(syllabus_topic_id=self.topic.id)
        self.file(user=self.hod, syllabus_topic_id=self.topic.id,
                  timetable_entry_id=self.period_for(self.hod, self.second).id)

        self.assertEqual(1, SyllabusTopicProgress.objects.filter(syllabus_topic_id=self.topic.id).count())

    def test_it_is_covered_for_the_class_that_was_taught_only(self):
        elsewhere = factories.ClassSectionFactory(school_class=self.section.school_class, name="B")

        self.file(syllabus_topic_id=self.topic.id)

        self.assertTrue(self.covered())
        self.assertFalse(self.covered(section=elsewhere), "8 B has not been taught it")

    def test_a_topic_of_another_subject_is_refused(self):
        """It would tick the wrong syllabus, silently."""
        other_subject = factories.SubjectFactory(school=self.school, name="History")
        stranger = factories.SyllabusTopicFactory(
            subject=other_subject, school=self.school, title="The Mughals", sequence_number=1
        )

        response = self.file(syllabus_topic_id=stranger.id)

        self.assertEqual(422, response.status_code)
        self.assertIn("syllabus_topic_id", self.errors(response))
        self.assertFalse(SyllabusTopicProgress.objects.exists())

    def test_a_topic_that_does_not_exist_is_refused(self):
        response = self.file(syllabus_topic_id=9_999_999)

        self.assertEqual(422, response.status_code)
        self.assertIn("syllabus_topic_id", self.errors(response))

    def test_a_report_refused_before_it_is_written_ticks_nothing(self):
        response = self.file(syllabus_topic_id=self.topic.id, report_date="2026-01-03")

        self.assertEqual(422, response.status_code)
        self.assertFalse(SyllabusTopicProgress.objects.exists())

    def test_a_tick_that_fails_takes_the_report_down_with_it(self):
        """The two are one transaction, and this is the only case that
        proves it. A report refused by validation never reaches the service
        at all, so asserting on that one would pass whether the transaction
        were there or not - it did, until a sabotage pass said so.
        """
        with mock.patch(
            "school.services.SyllabusTopicProgress.objects.get_or_create",
            side_effect=RuntimeError("the syllabus write failed"),
        ):
            # The API turns an unhandled error into a 500 rather than
            # letting it out, so the status is what there is to assert on.
            response = self.file(syllabus_topic_id=self.topic.id)

        self.assertEqual(500, response.status_code)

        self.assertFalse(
            DailyTeachingReport.objects.exists(),
            "a report filed but never credited to the syllabus is the half-done state the transaction exists to prevent",
        )
        self.assertFalse(SyllabusTopicProgress.objects.exists())

    def test_the_tick_is_audited_the_way_the_syllabus_screen_audits_one(self):
        self.file(syllabus_topic_id=self.topic.id)

        entry = AuditLog.objects.filter(action="syllabus_topic.ticked").first()

        self.assertIsNotNone(entry, "one trail answers when a topic was ticked, and by what")
        self.assertEqual("daily_teaching_report", entry.new_values["from"])

    def test_the_list_costs_no_query_per_report(self):
        for index in range(4):
            entry = self.period_for(self.teacher, factories.PeriodFactory(school=self.school, period_number=10 + index))
            self.file(timetable_entry_id=entry.id, syllabus_topic_id=self.topic.id)

        with CaptureQueriesContext(connection) as many:
            self.as_user(self.teacher).get("/api/v1/teaching-reports")

        self.assertLess(len(many), 15, "the topic should ride on the existing select_related")


class MyReports(TeachingReportCase):
    """`GET teaching-reports?mine=1` - the app's Reports list
    (docs/teacher-app.md, T3): only the caller's own, whatever else they may
    see."""

    def mine(self, user):
        response = self.as_user(user).get("/api/v1/teaching-reports", {"mine": 1})
        self.assertEqual(200, response.status_code)

        return [row["teacher_id"] for row in response.data["data"]]

    def test_an_hod_sees_only_their_own_not_their_departments(self):
        self.assertEqual(201, self.file().status_code)
        entry = self.period_for(self.hod, self.second)
        self.assertEqual(201, self.file(self.hod, timetable_entry_id=entry.id).status_code)

        self.assertEqual([self.hod.id], self.mine(self.hod))

    def test_an_hod_sees_their_own_even_from_outside_the_department_they_head(self):
        # Their own profile sits in Arts while they head Science: the
        # department view leaves them out, and "mine" must not.
        self.hod.staffprofile.department = self.arts
        self.hod.staffprofile.save()
        entry = self.period_for(self.hod, self.second)
        self.assertEqual(201, self.file(self.hod, timetable_entry_id=entry.id).status_code)

        self.assertEqual([self.hod.id], self.mine(self.hod))

    def test_an_admin_asking_for_mine_gets_none_of_the_schools_reports(self):
        self.assertEqual(201, self.file().status_code)

        self.assertEqual([], self.mine(self.admin))

    def test_mine_overrides_a_teacher_id_for_somebody_else(self):
        self.assertEqual(201, self.file().status_code)
        response = self.as_user(self.hod).get(
            "/api/v1/teaching-reports", {"mine": 1, "teacher_id": self.teacher.id}
        )

        self.assertEqual([], response.data["data"])

    def test_another_schools_teacher_sees_none_of_these(self):
        self.assertEqual(201, self.file().status_code)
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.TEACHER)

        self.assertEqual([], self.mine(stranger))


class OneReport(TeachingReportCase):
    """`GET teaching-reports/{id}` - a report opened from its period on the
    app's Today."""

    def setUp(self):
        super().setUp()
        response = self.file(homework="Exercise 4.2")
        self.assertEqual(201, response.status_code)
        self.report_id = response.data["id"]

    def read(self, user, report_id=None):
        return self.as_user(user).get(f"/api/v1/teaching-reports/{report_id or self.report_id}")

    def test_its_author_reads_it(self):
        response = self.read(self.teacher)

        self.assertEqual(200, response.status_code)
        self.assertEqual("Exercise 4.2", response.data["homework"])

    def test_the_hod_of_the_authors_department_reads_it(self):
        self.assertEqual(200, self.read(self.hod).status_code)

    def test_an_admin_of_the_school_reads_it(self):
        self.assertEqual(200, self.read(self.admin).status_code)

    def test_an_hod_reads_their_own_from_outside_the_department_they_head(self):
        self.hod.staffprofile.department = self.arts
        self.hod.staffprofile.save()
        entry = self.period_for(self.hod, self.second)
        own = self.file(self.hod, timetable_entry_id=entry.id).data["id"]

        self.assertEqual(200, self.read(self.hod, own).status_code)

    def test_another_teacher_gets_not_found(self):
        colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        self.assertEqual(404, self.read(colleague).status_code)

    def test_another_schools_admin_gets_not_found(self):
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        self.assertEqual(404, self.read(stranger).status_code)

    def test_a_role_without_reports_is_refused(self):
        staff = factories.UserFactory(school=self.school, role=UserRole.STAFF)

        self.assertEqual(403, self.read(staff).status_code)

    def test_a_missing_report_is_not_found(self):
        self.assertEqual(404, self.read(self.teacher, 999999).status_code)


class NotBeforeTheLessonBegins(TeachingReportCase):
    """A report says what a lesson covered, so today's waits until the
    period has begun, on the school's own clock. Period 1 runs 09:00-09:45;
    the school is in Kolkata."""

    MONDAY = "2026-10-26"

    def at(self, hour, minute):
        # IST is UTC+5:30.
        utc = dt.datetime(2026, 10, 26, hour, minute, tzinfo=dt.timezone.utc) - dt.timedelta(hours=5, minutes=30)
        return mock.patch("django.utils.timezone.now", return_value=utc)

    def test_refused_before_the_period_starts(self):
        with self.at(8, 55):
            response = self.file(report_date=self.MONDAY)

        self.assertEqual(422, response.status_code)
        self.assertIn("has not started yet", str(response.data["details"]))
        self.assertFalse(DailyTeachingReport.objects.exists())

    def test_accepted_from_the_moment_it_starts(self):
        with self.at(9, 0):
            self.assertEqual(201, self.file(report_date=self.MONDAY).status_code)

    def test_accepted_once_it_is_over(self):
        with self.at(15, 0):
            self.assertEqual(201, self.file(report_date=self.MONDAY).status_code)

    def test_an_earlier_day_is_never_too_early(self):
        with self.at(8, 0):
            self.assertEqual(201, self.file(report_date="2026-10-19").status_code)


class ToReview(TeachingReportCase):
    """`GET teaching-reports?to_review=1` - the HOD's queue in the app's
    Department tab (docs/teacher-app.md, T7): their department's reports
    nobody has reviewed yet, never their own."""

    def ids(self, user):
        response = self.as_user(user).get("/api/v1/teaching-reports", {"to_review": 1})
        self.assertEqual(200, response.status_code)
        return [row["id"] for row in response.data["data"]]

    def test_an_hod_sees_their_departments_unreviewed_reports(self):
        waiting = self.file().data["id"]

        self.assertEqual([waiting], self.ids(self.hod))

    def test_a_reviewed_report_leaves_the_queue(self):
        report = self.file().data["id"]
        self.assertEqual(200, self.as_user(self.hod).patch(f"/api/v1/teaching-reports/{report}/review").status_code)

        self.assertEqual([], self.ids(self.hod))

    def test_the_hods_own_report_is_never_in_their_queue(self):
        entry = self.period_for(self.hod, self.second)
        self.assertEqual(201, self.file(self.hod, timetable_entry_id=entry.id).status_code)

        self.assertEqual([], self.ids(self.hod))

    def test_another_departments_reports_are_not_in_it(self):
        outsider = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.employee(outsider, self.arts)
        entry = self.period_for(outsider, self.second)
        self.assertEqual(201, self.file(outsider, timetable_entry_id=entry.id).status_code)

        self.assertEqual([], self.ids(self.hod))

    def test_a_teacher_has_nothing_to_review(self):
        self.assertEqual(201, self.file().status_code)

        self.assertEqual([], self.ids(self.teacher))

    def test_a_teacher_may_not_review_even_by_asking_directly(self):
        colleague = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.employee(colleague, self.science)
        report = self.file().data["id"]

        self.assertEqual(403, self.as_user(colleague).patch(f"/api/v1/teaching-reports/{report}/review").status_code)

    def test_an_hod_of_another_school_may_not_review(self):
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.HOD)
        report = self.file().data["id"]

        self.assertIn(
            self.as_user(stranger).patch(f"/api/v1/teaching-reports/{report}/review").status_code, (403, 404)
        )

"""The chains that have to stay automatic (docs/insights.md, slice 5).

Every one of these is a place where doing one thing in the product does a
second thing on its own. They are spread across five modules and none of
them is obvious from the code that benefits: the dashboard does not know
that marking a register queued an alert, and the Syllabus screen does not
know a teaching report ticked it.

So they are pinned here, in one file, as a list somebody can read. A
refactor that quietly breaks one of them fails here with a name that says
what a school would notice.
"""

from __future__ import annotations

import datetime as dt
from unittest import mock

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone

from school import factories
from school.enums import (
    AssessmentStatus,
    LeaveStatus,
    MessageEvent,
    StaffAttendanceStatus,
    UserRole,
)
from school.models import (
    AssessmentMark,
    CommunicationSetting,
    DailyTeachingReport,
    Message,
    StaffAttendance,
    QueuedJob,
    StudentEnrollment,
    SyllabusTopicProgress,
)
from school.services import (
    AttendanceService,
    DailyTeachingReportService,
    StaffLeaveService,
    StudentService,
)

A_MONDAY = dt.date(2026, 9, 14)
NOW = dt.datetime(2026, 9, 14, 9, 0, tzinfo=dt.timezone.utc)


class ChainTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.school = factories.SchoolFactory(timezone="UTC")
        self.year = factories.AcademicYearFactory(school=self.school, is_current=True)
        self.department = factories.DepartmentFactory(school=self.school)
        self.subject = factories.SubjectFactory(school=self.school, department=self.department, name="Physics")
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=self.year, school=self.school),
            class_teacher=self.teacher,
        )
        self.student = factories.StudentFactory(
            class_section=self.section, guardian_mobile="+91 90000 00001", guardian_email="g@example.com"
        )

    def alerts_on(self) -> None:
        """A school that has never opened the settings screen gets the
        defaults, and the defaults send absence alerts by SMS."""
        cache.clear()


class MarkingARegisterTellsTheGuardians(ChainTestCase):
    """Attendance -> the guardian's phone."""

    def submit(self, status: str) -> None:
        AttendanceService.submit(
            self.section,
            {"attendance_date": A_MONDAY, "records": [{"student_id": self.student.id, "status": status}]},
            self.teacher,
        )

    def test_marking_a_child_absent_queues_a_message_without_anybody_writing_one(self):
        self.submit("absent")

        message = Message.objects.filter(event=MessageEvent.ATTENDANCE_ABSENT).first()

        self.assertIsNotNone(message, "marking the register is the only entry a teacher should have to make")
        self.assertEqual(self.student.id, message.student_id)

    def test_the_school_decides_which_statuses_go_out(self):
        """The default is absences only. A present mark sends nothing and
        logs nothing - a school that wanted every child's arrival texted
        home would have asked for it."""
        self.submit("present")

        self.assertFalse(Message.objects.filter(event=MessageEvent.ATTENDANCE_PRESENT).exists())


class ApprovingLeaveWritesTheRegister(ChainTestCase):
    """Leave -> staff attendance, so the two can never disagree about
    whether somebody was expected in."""

    def test_an_approved_request_marks_every_working_day_in_its_range(self):
        profile = factories.StaffProfileFactory(school=self.school, user=self.teacher, department=self.department)
        leave = factories.StaffLeaveFactory(
            staff_profile=profile,
            school=self.school,
            start_date=A_MONDAY,
            end_date=A_MONDAY + dt.timedelta(days=1),
            status=LeaveStatus.PENDING,
        )

        StaffLeaveService.approve(leave, self.admin, "Fine.")

        marked = StaffAttendance.objects.filter(staff_profile=profile, status=StaffAttendanceStatus.LEAVE)

        self.assertEqual(
            {A_MONDAY, A_MONDAY + dt.timedelta(days=1)},
            {row.attendance_date for row in marked},
            "nobody should have to mark the register for leave the school already approved",
        )


class PublishingAResultTellsTheGuardians(ChainTestCase):
    """A published result -> the guardian's phone, once and only once."""

    def publish(self):
        from school.services import AssessmentPublishService

        term = factories.AcademicTermFactory(academic_year=self.year, school=self.school)
        assessment = factories.AssessmentFactory(
            class_section=self.section, school=self.school, academic_year=self.year, academic_term=term,
            subject=self.subject, max_marks=20, assessment_date=A_MONDAY, status=AssessmentStatus.DRAFT,
            created_by=self.teacher,
        )
        AssessmentMark.objects.create(
            school=self.school, assessment=assessment, student=self.student, marks_obtained=18,
            is_absent=False, entered_by=self.teacher, created_at=NOW, updated_at=NOW,
        )

        return AssessmentPublishService.publish(assessment, self.teacher)

    def test_publishing_hands_the_telling_off_to_the_queue(self):
        """The fan-out is queued rather than done inline: a class of forty
        guardians must not be forty gateway calls between the teacher and
        their saved sheet."""
        self.publish()

        self.assertTrue(
            QueuedJob.objects.filter(name="announce_results").exists(),
            "entering marks and publishing should be the whole of it",
        )

    def test_the_queued_fan_out_reaches_the_guardian(self):
        from school import jobs

        assessment = self.publish()
        jobs.announce_results(assessment_id=assessment.id, actor_id=self.teacher.id)

        self.assertTrue(
            Message.objects.filter(event=MessageEvent.RESULT_PUBLISHED, student_id=self.student.id).exists()
        )

    def test_publishing_twice_does_not_tell_a_family_twice(self):
        """Reopening to fix one mark and publishing again must not send the
        same result to the same family a second time."""
        from school import jobs
        from school.services import AssessmentPublishService

        assessment = self.publish()
        jobs.announce_results(assessment_id=assessment.id, actor_id=self.teacher.id)
        sent = Message.objects.filter(event=MessageEvent.RESULT_PUBLISHED).count()

        AssessmentPublishService.reopen(assessment, self.admin)
        AssessmentPublishService.publish(assessment, self.teacher)
        jobs.announce_results(assessment_id=assessment.id, actor_id=self.teacher.id)

        self.assertEqual(sent, Message.objects.filter(event=MessageEvent.RESULT_PUBLISHED).count())


class FilingAReportTicksTheSyllabus(ChainTestCase):
    """A daily teaching report -> syllabus progress (slice 3)."""

    def test_naming_a_topic_marks_it_covered_for_the_class(self):
        topic = factories.SyllabusTopicFactory(subject=self.subject, school=self.school, sequence_number=1)
        entry = factories.TimetableEntryFactory(
            school=self.school, class_section=self.section, subject=self.subject,
            teacher=self.teacher, day_of_week="monday",
            period=factories.PeriodFactory(school=self.school),
        )

        DailyTeachingReportService.create(
            entry,
            {"report_date": A_MONDAY, "topic_taught": "Newton's laws", "syllabus_topic_id": topic.id},
            self.teacher,
        )

        self.assertTrue(
            SyllabusTopicProgress.objects.filter(syllabus_topic=topic, class_section=self.section).exists(),
            "the teacher should not have to tick the same topic on the Syllabus screen",
        )


class AdmittingAStudentRecordsTheirYear(ChainTestCase):
    """A student -> their enrollment history, so a promotion has something
    to promote from."""

    def test_a_new_student_has_a_row_for_the_year_they_joined(self):
        student = StudentService.create(
            {
                "school_id": self.school.id,
                "class_section_id": self.section.id,
                "admission_number": "ADM-NEW",
                "first_name": "Nita",
                "last_name": "Rao",
                "guardian_name": "Rao",
                "guardian_mobile": "+91 90000 00009",
            },
            self.admin,
        )

        self.assertTrue(
            StudentEnrollment.objects.filter(student=student, academic_year=self.year).exists(),
            "a student with no enrolled year cannot be promoted out of one",
        )


class NobodyIsChasedForAPeriodTheyWereOnLeaveFor(ChainTestCase):
    """Approved leave -> no pending teaching report.

    The leave is already approved and already written to the staff
    register. Counting its periods as "pending" asks a teacher for a report
    on a day the school knows they were not there, and leaves an HOD
    chasing it.
    """

    def setUp(self):
        super().setUp()
        self.profile = factories.StaffProfileFactory(
            school=self.school, user=self.teacher, department=self.department
        )
        self.entry = factories.TimetableEntryFactory(
            school=self.school, class_section=self.section, subject=self.subject,
            teacher=self.teacher, day_of_week="monday",
            period=factories.PeriodFactory(school=self.school),
        )

    def summary(self, user=None) -> dict:
        return DailyTeachingReportService.summary(user or self.admin, {}, A_MONDAY)

    def approve_leave_covering(self, day: dt.date) -> None:
        leave = factories.StaffLeaveFactory(
            staff_profile=self.profile, school=self.school,
            start_date=day, end_date=day, status=LeaveStatus.PENDING,
        )
        StaffLeaveService.approve(leave, self.admin, "Fine.")

    def test_a_period_is_scheduled_while_the_teacher_is_expected_in(self):
        self.assertEqual(1, self.summary()["scheduled"])
        self.assertEqual(1, self.summary()["pending"])

    def test_an_approved_leave_takes_the_period_off_the_pending_count(self):
        self.approve_leave_covering(A_MONDAY)

        self.assertEqual(0, self.summary()["scheduled"])
        self.assertEqual(0, self.summary()["pending"])

    def test_leave_on_another_day_changes_nothing(self):
        self.approve_leave_covering(A_MONDAY + dt.timedelta(days=1))

        self.assertEqual(1, self.summary()["scheduled"])

    def test_a_request_still_waiting_changes_nothing(self):
        """An unapproved request is somebody's hope, not the school's
        decision."""
        factories.StaffLeaveFactory(
            staff_profile=self.profile, school=self.school,
            start_date=A_MONDAY, end_date=A_MONDAY, status=LeaveStatus.PENDING,
        )

        self.assertEqual(1, self.summary()["scheduled"])

    def test_a_rejected_request_changes_nothing(self):
        leave = factories.StaffLeaveFactory(
            staff_profile=self.profile, school=self.school,
            start_date=A_MONDAY, end_date=A_MONDAY, status=LeaveStatus.PENDING,
        )
        StaffLeaveService.reject(leave, self.admin, "Not this week.")

        self.assertEqual(1, self.summary()["scheduled"])

    def test_another_teachers_leave_does_not_excuse_this_one(self):
        other = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        other_profile = factories.StaffProfileFactory(
            school=self.school, user=other, department=self.department
        )
        leave = factories.StaffLeaveFactory(
            staff_profile=other_profile, school=self.school,
            start_date=A_MONDAY, end_date=A_MONDAY, status=LeaveStatus.PENDING,
        )
        StaffLeaveService.approve(leave, self.admin, "Fine.")

        self.assertEqual(1, self.summary()["scheduled"])

    def test_a_report_filed_anyway_still_counts_as_submitted(self):
        """Somebody covered the lesson and filed for it. The report is real
        and the count must not go negative."""
        self.approve_leave_covering(A_MONDAY)
        DailyTeachingReport.objects.create(
            school=self.school, timetable_entry=self.entry, teacher=self.teacher,
            report_date=A_MONDAY, topic_taught="Covered by a colleague",
            created_at=NOW, updated_at=NOW,
        )

        summary = self.summary()

        self.assertEqual(1, summary["submitted"])
        self.assertEqual(0, summary["pending"])

    def test_the_teachers_own_dashboard_says_the_same_thing(self):
        """Two screens, one answer. A dashboard reading "0/2 filed" in
        warning orange beside a Teaching Reports screen reading "0 pending"
        would be the product arguing with itself.
        """
        from school.dashboard import DashboardService

        before = {card["key"]: card["value"] for card in DashboardService.for_user(self.teacher, None)["cards"]}
        self.assertEqual("1", before["periods"])
        self.assertEqual("0/1", before["reports"])

        self.approve_leave_covering(A_MONDAY)

        after = {card["key"]: card["value"] for card in DashboardService.for_user(self.teacher, None)["cards"]}
        self.assertEqual("0", after["periods"])
        self.assertEqual("0/0", after["reports"])


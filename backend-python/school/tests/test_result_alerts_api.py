"""Telling the guardian a result was published (docs/assessments.md).

Publishing is the moment a test stops being the school's own business, so it
is also the moment the family hears about it. Everything here is about who
hears what, and - more often - who deliberately hears nothing:

- a school with messaging or result alerts switched off records nothing at
  all, not even a skip, because it never wanted the message;
- a guardian with no mobile number is a skipped row with a reason, because
  the school did want it and the missing number is worth fixing;
- an absentee's guardian hears nothing: there is no result to report;
- republishing after a reopen sends nothing, so a corrected mark does not
  tell a whole class's families twice.

The fan-out is a queued job. Every test here runs the worker the way the
cron would, which is also the check that publishing itself never waits on it.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from django.utils import timezone
from rest_framework.test import APIClient

from school import factories, notifications, queue, tokens
from school.enums import (
    AttendanceAlertMode,
    MessageChannel,
    MessageEvent,
    MessageStatus,
    StudentStatus,
    UserRole,
)
from school.clock import SchoolClock
from school.models import (
    Assessment,
    AssessmentMark,
    CommunicationSetting,
    Message,
    MessageTemplate,
    ModuleSetting,
    QueuedJob,
)
from school.services import AssessmentPublishService

ASSESSMENTS = "/api/v1/assessments"


class ResultAlertTestCase(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory(name="Green Valley", timezone="Asia/Kolkata")
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.term = factories.AcademicTermFactory(
            academic_year=self.year,
            school=self.school,
            name="Term 1",
            sequence_number=1,
            start_date=dt.date(2026, 4, 1),
            end_date=dt.date(2026, 8, 31),
        )
        self.school_class = factories.SchoolClassFactory(
            academic_year=self.year, school=self.school, name="Grade 8", level=8
        )
        self.section = factories.ClassSectionFactory(school_class=self.school_class, name="A")
        self.department = factories.DepartmentFactory(school=self.school, name="Mathematics")
        self.subject = factories.SubjectFactory(
            department=self.department, school=self.school, name="Mathematics", min_class_level=1, max_class_level=12
        )
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        factories.TimetableEntryFactory(
            school=self.school,
            class_section=self.section,
            subject=self.subject,
            teacher=self.teacher,
            period=factories.PeriodFactory(school=self.school),
        )

        self.scale = factories.GradeScaleFactory(school=self.school, name="Secondary")
        for label, low, high in (("A1", 91, 100), ("A2", 81, 90), ("Pass", 33, 80), ("Fail", 0, 32)):
            factories.GradeBandFactory(
                grade_scale=self.scale, label=label, min_percentage=low, max_percentage=high, is_failing=label == "Fail"
            )

        self.aarav = factories.StudentFactory(
            school=self.school,
            class_section=self.section,
            first_name="Aarav",
            admission_number="ADM-1",
            guardian_name="Meera Sharma",
            guardian_mobile="+91 98765 43210",
        )
        self.bina = factories.StudentFactory(
            school=self.school,
            class_section=self.section,
            first_name="Bina",
            admission_number="ADM-2",
            guardian_name="Rekha Patel",
            guardian_mobile="+91 98765 43211",
        )

        self.assessment = factories.AssessmentFactory(
            school=self.school,
            academic_year=self.year,
            academic_term=self.term,
            class_section=self.section,
            subject=self.subject,
            title="Unit Test 1",
            max_marks=20,
            grade_scale=self.scale,
            created_by=self.teacher,
        )
        self.client = self.as_user(self.teacher)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def url(self, action: str) -> str:
        return f"{ASSESSMENTS}/{self.assessment.id}/{action}"

    def mark_everybody(self, first="19", second="8"):
        self.client.put(
            self.url("marks"),
            {
                "marks": [
                    {"student_id": self.aarav.id, "marks_obtained": first},
                    {"student_id": self.bina.id, "marks_obtained": second},
                ]
            },
            format="json",
        )

    def publish(self, run_worker: bool = True):
        response = self.client.post(self.url("publish"))

        if run_worker:
            queue.work()

        return response

    def reopen(self):
        """Taking a result back is an administrator's act - never a teacher's."""
        response = self.as_user(self.admin).post(self.url("reopen"))
        assert response.status_code == 200, response.data

        return response

    def settings_row(self, **fields) -> CommunicationSetting:
        """A school that has opened the settings screen. Reading alone never
        writes a row, so a test that wants a switch off has to save one."""
        values = dict(notifications.DEFAULTS)
        values.update(fields)

        return CommunicationSetting.objects.create(
            school=self.school, created_at=timezone.now(), updated_at=timezone.now(), **values
        )

    def messages(self, channel: str = MessageChannel.SMS):
        return Message.objects.filter(event=MessageEvent.RESULT_PUBLISHED, channel=channel).order_by("id")

    def announced_at(self):
        return Assessment.objects.values_list("results_announced_at", flat=True).get(pk=self.assessment.id)


class TheGuardianHears(ResultAlertTestCase):
    def test_every_marked_child_gets_their_own_result(self):
        self.mark_everybody()

        self.publish()

        sent = list(self.messages())
        self.assertEqual(2, len(sent), [m.body for m in sent])
        self.assertEqual(["Meera Sharma", "Rekha Patel"], [message.recipient_name for message in sent])
        self.assertEqual(MessageStatus.SENT, sent[0].status, "the log gateway takes it")
        self.assertIn("Aarav", sent[0].body)
        self.assertNotIn("Bina", sent[0].body, "a guardian hears about their own child only")

    def test_the_wording_carries_the_marks_the_test_and_the_grade(self):
        self.mark_everybody()

        self.publish()

        body = self.messages().first().body
        self.assertIn("19/20", body, "17.50 reads as 17.5 and 20.00 as 20")
        self.assertIn("A1", body)
        self.assertIn("Unit Test 1", body)
        self.assertIn("Mathematics", body)
        self.assertIn("Green Valley", body)

    def test_a_school_with_no_grade_scale_sends_marks_without_leaving_a_gap(self):
        Assessment.objects.filter(pk=self.assessment.id).update(grade_scale=None)
        self.mark_everybody()

        self.publish()

        body = self.messages().first().body
        self.assertIn("19/20 in Unit Test 1", body, "the blank grade closes up rather than doubling the space")
        self.assertNotIn("{", body, "a token the sender has nothing for never leaks braces")

    def test_a_half_mark_reads_as_a_person_would_write_it(self):
        self.mark_everybody(first="17.5")

        self.publish()

        self.assertIn("17.5/20", self.messages().first().body)

    def test_the_fan_out_is_queued_rather_than_sent_while_the_teacher_waits(self):
        self.mark_everybody()

        response = self.publish(run_worker=False)

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(0, self.messages().count(), "nothing is written until the worker runs")
        self.assertTrue(
            QueuedJob.objects.filter(name="announce_results").exists(), "publishing queued the fan-out instead"
        )

        queue.work()
        self.assertEqual(2, self.messages().count())

    def test_the_stamp_records_that_the_families_were_told(self):
        self.mark_everybody()

        self.assertIsNone(self.announced_at(), "nobody has been told before it is published")
        self.publish()
        self.assertIsNotNone(self.announced_at())


class TheGuardianHearsNothing(ResultAlertTestCase):
    def test_an_absent_child_has_no_result_to_report(self):
        self.client.put(
            self.url("marks"),
            {
                "marks": [
                    {"student_id": self.aarav.id, "marks_obtained": "19"},
                    {"student_id": self.bina.id, "is_absent": True},
                ]
            },
            format="json",
        )

        self.publish()

        self.assertEqual(["Meera Sharma"], [message.recipient_name for message in self.messages()])

    def test_a_school_with_the_module_off_records_nothing_at_all(self):
        ModuleSetting.objects.create(
            school=self.school,
            module="communication",
            school_enabled=False,
            settings=None,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )
        self.mark_everybody()

        self.publish()

        self.assertEqual(0, Message.objects.count(), "a switched-off module is not a skipped message")
        self.assertIsNone(self.announced_at(), "and nobody has been told, honestly recorded")

    def test_a_school_with_result_alerts_off_records_nothing_either(self):
        self.settings_row(result_alerts_enabled=False)
        self.mark_everybody()

        self.publish()

        self.assertEqual(0, Message.objects.count())
        self.assertIsNone(self.announced_at())

    def test_switching_result_alerts_off_leaves_the_other_alerts_alone(self):
        self.settings_row(result_alerts_enabled=False, attendance_alerts=AttendanceAlertMode.PRESENT_AND_ABSENT)
        self.mark_everybody()
        self.publish()

        notifications.notify_guardian(MessageEvent.ATTENDANCE_ABSENT, self.aarav, {"class_name": "Grade 8 A"})

        self.assertEqual(0, self.messages().count())
        self.assertEqual(1, Message.objects.filter(event=MessageEvent.ATTENDANCE_ABSENT).count())

    def test_a_result_taken_back_before_the_worker_ran_is_not_announced(self):
        self.mark_everybody()
        self.publish(run_worker=False)

        self.reopen()
        queue.work()

        self.assertEqual(0, self.messages().count(), "the result they would hear about no longer stands")
        self.assertIsNone(self.announced_at())

    def test_republishing_a_corrected_result_tells_nobody_twice(self):
        self.mark_everybody()
        self.publish()
        first_told = self.announced_at()

        self.reopen()
        self.mark_everybody(first="20")
        self.publish()

        self.assertEqual(2, self.messages().count(), "the second publishing sent nothing")
        self.assertEqual(first_told, self.announced_at(), "and the stamp is the day they really were told")

    def test_a_child_who_has_left_is_not_messaged(self):
        self.mark_everybody()
        self.aarav.status = StudentStatus.INACTIVE
        self.aarav.save(update_fields=["status"])

        self.publish()

        self.assertEqual(["Rekha Patel"], [message.recipient_name for message in self.messages()])


class WhereTheGuardianCannotBeReached(ResultAlertTestCase):
    def test_a_guardian_with_no_mobile_number_is_a_skipped_row_with_a_reason(self):
        self.bina.guardian_mobile = None
        self.bina.save(update_fields=["guardian_mobile"])
        self.mark_everybody()

        self.publish()

        skipped = self.messages().get(recipient_name="Rekha Patel")
        self.assertEqual(MessageStatus.SKIPPED, skipped.status, "the school wanted this one - the number is missing")
        self.assertEqual(notifications.NO_MOBILE, skipped.failure_reason)
        self.assertEqual(MessageStatus.SENT, self.messages().get(recipient_name="Meera Sharma").status)

    def test_an_email_address_and_no_mobile_still_reaches_them_by_email(self):
        self.settings_row(email_enabled=True)
        self.bina.guardian_mobile = None
        self.bina.guardian_email = "rekha@example.com"
        self.bina.save(update_fields=["guardian_mobile", "guardian_email"])
        self.mark_everybody()

        self.publish()

        emailed = self.messages(MessageChannel.EMAIL).get(recipient_name="Rekha Patel")
        self.assertEqual("rekha@example.com", emailed.recipient_email)
        self.assertEqual(MessageStatus.SKIPPED, self.messages().get(recipient_name="Rekha Patel").status)

    def test_a_class_nobody_can_be_reached_in_still_counts_as_told(self):
        for student in (self.aarav, self.bina):
            student.guardian_mobile = None
            student.save(update_fields=["guardian_mobile"])
        self.mark_everybody()

        self.publish()

        self.assertEqual(2, self.messages().filter(status=MessageStatus.SKIPPED).count())
        self.assertIsNotNone(self.announced_at(), "the school was told who was missed; repeating it helps nobody")


class TheServiceItself(ResultAlertTestCase):
    """The rules that a request cannot reach directly, pinned where they live."""

    def test_announcing_a_second_time_tells_nobody_twice(self):
        """The rule lives in the service, not only in what publishing queues.

        A queued job can be retried, and a republish queues nothing - but
        neither of those is what makes this safe. This is.
        """
        self.mark_everybody()
        self.publish()

        self.assertEqual(0, AssessmentPublishService.announce(self.assessment.id, self.teacher))
        self.assertEqual(2, self.messages().count(), "the class was messaged once, by the first publishing")

    def test_announcing_a_draft_sends_nothing(self):
        self.mark_everybody()

        self.assertEqual(0, AssessmentPublishService.announce(self.assessment.id, self.teacher))
        self.assertEqual(0, Message.objects.count())

    def test_announcing_a_test_that_has_gone_sends_nothing(self):
        self.assertEqual(0, AssessmentPublishService.announce(self.assessment.id + 9999, self.teacher))

    def test_a_message_that_cannot_be_written_does_not_undo_the_publishing(self):
        self.mark_everybody()
        self.publish(run_worker=False)

        # A student row that has gone between the publish and the job: the
        # fan-out must not take the publishing down with it.
        AssessmentMark.objects.filter(assessment_id=self.assessment.id).delete()
        queue.work()

        self.assertFalse(Assessment.objects.get(pk=self.assessment.id).is_draft(), "still published")

    def test_the_date_in_the_message_is_the_school_s_own(self):
        """A school reading {date} gets the date where the school is.

        Half past eight in the evening in London is already tomorrow in
        Kolkata, so a naive server date would put the wrong day in a parent's
        text.
        """
        MessageTemplate.objects.create(
            school=self.school,
            event=MessageEvent.RESULT_PUBLISHED,
            body="{student_name}: {marks}/{max_marks} on {date}",
            is_active=True,
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )
        self.mark_everybody()

        self.publish()

        today = SchoolClock.for_school(self.school.id).now().strftime("%m/%d/%Y")
        self.assertEqual(f"{self.aarav.name}: 19/20 on {today}", self.messages().first().body)

    def test_the_tokens_name_the_class_the_term_and_the_percentage(self):
        self.mark_everybody()

        supplied = AssessmentPublishService.tokens_for(
            Assessment.objects.select_related("class_section__school_class", "subject", "academic_term").get(
                pk=self.assessment.id
            ),
            AssessmentMark.objects.get(assessment_id=self.assessment.id, student_id=self.aarav.id),
        )

        self.assertEqual("Grade 8 A", supplied["class_name"])
        self.assertEqual("Term 1", supplied["term_name"])
        self.assertEqual("95", supplied["percentage"])
        self.assertEqual("Class Test", supplied["assessment_type"])

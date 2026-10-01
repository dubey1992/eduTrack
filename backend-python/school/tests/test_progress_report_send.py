"""Sending a progress report to a guardian (docs/insights.md, slice 4).

Staff choose when. Nothing goes out at a term boundary on its own: this is
a document about a child, and somebody should have looked at it first.

Built on the progress report's own tests, so the figures inside the page
are already pinned there and what is pinned here is the sending - who may,
what is refused, and what the row in the log says afterwards.
"""

from __future__ import annotations

from unittest import mock

from django.core.cache import cache
from django.utils import timezone

from school import factories, jobs, notifications
from school.enums import MessageChannel, MessageEvent, MessageStatus, UserRole
from school.models import CommunicationSetting, Message
from school.tests.test_progress_report_api import ProgressReportTestCase


class SendingItToTheGuardian(ProgressReportTestCase):
    def setUp(self):
        super().setUp()
        self.student.guardian_email = "guardian@example.com"
        self.student.save()
        self.email_is_on()

    def email_is_on(self, enabled: bool = True) -> None:
        """Email is off until a school configures it - that is the product
        default, not an oversight - so a test about sending has to turn it
        on the way a school would."""
        CommunicationSetting.objects.filter(school=self.school).delete()
        CommunicationSetting.objects.create(
            school=self.school,
            **{**notifications.DEFAULTS, "email_enabled": enabled},
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )
        cache.clear()

    def send(self, client=None, student=None, **params):
        return (client or self.client).post(
            f"/api/v1/students/{(student or self.student).id}/progress-report/send", params
        )

    def queued(self) -> list:
        return list(Message.objects.filter(event=MessageEvent.PROGRESS_REPORT))

    def test_a_published_term_is_queued_to_the_guardian(self):
        self.mark(self.published(), marks="18")

        response = self.send()

        self.assertEqual(202, response.status_code, response.data)
        self.assertEqual("guardian@example.com", response.data["recipient_email"])

        message = self.queued()[0]
        self.assertEqual(MessageChannel.EMAIL, message.channel)
        self.assertEqual(MessageStatus.QUEUED, message.status)
        self.assertEqual(self.student.id, message.student_id)
        self.assertIn("Aarav", message.body)

    def test_it_goes_by_email_only(self):
        """A text saying "the report is attached" with nothing attached
        would be a lie the school did not tell."""
        self.student.guardian_mobile = "+91 90000 00001"
        self.student.save()
        self.mark(self.published(), marks="18")

        self.send()

        self.assertEqual([MessageChannel.EMAIL], [message.channel for message in self.queued()])

    def test_a_school_that_has_never_set_email_up_sends_nothing(self):
        """Email is off until a school configures SMTP. The default is not
        an oversight, and somebody pressing Send is told what it is."""
        CommunicationSetting.objects.filter(school=self.school).delete()
        cache.clear()
        self.mark(self.published(), marks="18")

        response = self.send()

        self.assertEqual(409, response.status_code)
        self.assertEqual("EMAIL_NOT_SENT", response.data["code"])

    def test_a_term_with_nothing_published_is_refused(self):
        response = self.send()

        self.assertEqual(422, response.status_code)
        self.assertEqual("NOTHING_TO_REPORT", response.data["code"])
        self.assertEqual([], self.queued())

    def test_a_draft_is_still_nothing_to_send(self):
        self.mark(self.draft(), marks="20")

        self.assertEqual(422, self.send().status_code)
        self.assertEqual([], self.queued())

    def test_a_student_with_no_guardian_email_is_refused_plainly(self):
        self.student.guardian_email = ""
        self.student.save()
        self.mark(self.published(), marks="18")

        response = self.send()

        self.assertEqual(422, response.status_code)
        self.assertEqual("NO_GUARDIAN_EMAIL", response.data["code"])
        self.assertEqual([], self.queued())

    def test_a_school_with_email_switched_off_is_told_rather_than_left_wondering(self):
        """A switched-off channel records nothing anywhere in the product,
        which would otherwise leave somebody who pressed Send with no
        message and no explanation (docs/settings.md)."""
        self.mark(self.published(), marks="18")
        self.email_is_on(False)

        response = self.send()

        self.assertEqual(409, response.status_code)
        self.assertEqual("EMAIL_NOT_SENT", response.data["code"])
        self.assertEqual([], self.queued())

    def test_it_sends_the_term_that_was_asked_for(self):
        self.mark(self.published(term=self.term_1), marks="18")

        response = self.send(academic_term_id=self.term_1.id)

        self.assertEqual(202, response.status_code, response.data)
        self.assertIn("Term 1", self.queued()[0].body)

    def test_whoever_may_print_it_may_send_it(self):
        self.mark(self.published(), marks="18")
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.section.class_teacher = teacher
        self.section.save()

        self.assertEqual(202, self.send(client=self.as_user(teacher)).status_code)

    def test_a_teacher_of_another_class_may_not(self):
        self.mark(self.published(), marks="18")
        other = factories.ClassSectionFactory(school_class=self.school_class, name="B")
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        other.class_teacher = teacher
        other.save()

        self.assertEqual(403, self.send(client=self.as_user(teacher)).status_code)
        self.assertEqual([], self.queued())

    def test_another_schools_administrator_may_not(self):
        self.mark(self.published(), marks="18")
        stranger = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        self.assertIn(self.send(client=self.as_user(stranger)).status_code, (403, 404))
        self.assertEqual([], self.queued())


class CarryingIt(ProgressReportTestCase):
    """The job behind the send."""

    def setUp(self):
        super().setUp()
        self.student.guardian_email = "guardian@example.com"
        self.student.save()
        CommunicationSetting.objects.create(
            school=self.school,
            **{**notifications.DEFAULTS, "email_enabled": True},
            created_at=timezone.now(),
            updated_at=timezone.now(),
        )
        cache.clear()
        self.mark(self.published(), marks="18")

    def queue_one(self) -> Message:
        self.client.post(f"/api/v1/students/{self.student.id}/progress-report/send")

        return Message.objects.filter(event=MessageEvent.PROGRESS_REPORT).first()

    def test_it_emails_the_report_as_an_attachment_and_marks_the_row_sent(self):
        message = self.queue_one()

        with mock.patch("school.jobs.mailer.message") as build:
            jobs.send_progress_report(
                message_id=message.id, student_id=self.student.id, academic_term_id=self.term_2.id
            )

        mail = build.return_value
        name, blob, mime = mail.attach.call_args.args

        self.assertTrue(name.startswith("progress-report-"), name)
        self.assertTrue(blob.startswith(b"%PDF"))
        self.assertEqual("application/pdf", mime)
        mail.send.assert_called_once()

        message.refresh_from_db()
        self.assertEqual(MessageStatus.SENT, message.status)
        self.assertIsNotNone(message.sent_at)

    def test_a_mail_server_having_a_bad_morning_is_a_failed_row_with_a_reason(self):
        message = self.queue_one()

        with mock.patch("school.jobs.mailer.message") as build:
            build.return_value.send.side_effect = RuntimeError("connection refused")
            jobs.send_progress_report(message_id=message.id, student_id=self.student.id)

        message.refresh_from_db()
        self.assertEqual(MessageStatus.FAILED, message.status)
        self.assertIn("connection refused", message.failure_reason)

    def test_a_payload_naming_no_student_is_skipped_not_retried_for_ever(self):
        """A student cannot actually be deleted out from under a queued
        message - the messages table holds a foreign key to them - so what
        this guards is a stale or malformed payload. Skipped with a reason
        beats a worker retrying it until somebody notices.
        """
        message = self.queue_one()

        jobs.send_progress_report(message_id=message.id, student_id=9_999_999)

        message.refresh_from_db()
        self.assertEqual(MessageStatus.SKIPPED, message.status)

    def test_a_row_already_handled_is_left_alone(self):
        """Two workers taking the same job must not send twice."""
        message = self.queue_one()
        Message.objects.filter(pk=message.pk).update(status=MessageStatus.SENT)

        with mock.patch("school.jobs.mailer.message") as build:
            jobs.send_progress_report(message_id=message.id, student_id=self.student.id)

        build.assert_not_called()

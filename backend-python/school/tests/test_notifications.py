"""Telling somebody something happened.

The rule most easily lost in a port, and the one this file leans on hardest:
**a switched-off alert is not logged at all.** It is not "skipped" - the school
never wanted the message. Only a message the school *did* want but that could
not be delivered is worth a row, because one row per student per day would
bury the log that exists to be read.

The second is that nothing here talks to a gateway. Recording and sending are
separate, so a provider being down cannot roll back the register that caused
the message.
"""

from django.test import TestCase

from school import factories, notifications, queue, sms
from school.enums import (
    AttendanceAlertMode,
    MessageChannel,
    MessageEvent,
    MessageStatus,
    UserRole,
)
from school.models import CommunicationSetting, Message, MessageTemplate, QueuedJob


class NotificationTest(TestCase):
    def setUp(self):
        self.school = factories.SchoolFactory(name="Sunrise Public School")
        self.student = factories.StudentFactory(
            school=self.school,
            class_section=section_in(self.school),
            first_name="Aarav",
            last_name="Sharma",
            guardian_name="Meera Sharma",
            guardian_mobile="+91 9000000000",
        )

    def settings(self, **overrides) -> CommunicationSetting:
        values = dict(notifications.DEFAULTS)
        values.update(overrides)

        return CommunicationSetting.objects.create(school_id=self.school.id, **values)


class TheDefaults(NotificationTest):
    def test_a_school_that_has_never_opened_the_screen_gets_defaults(self):
        setting = notifications.settings_for(self.school.id)

        self.assertTrue(setting.sms_enabled)
        self.assertEqual(AttendanceAlertMode.ABSENT_ONLY, setting.attendance_alerts)

    def test_reading_the_settings_does_not_create_a_row(self):
        # Asking a question should not be a write. A settings table with a row
        # per school that has merely been looked at is a table nobody can
        # reason about.
        notifications.settings_for(self.school.id)

        self.assertEqual(0, CommunicationSetting.objects.count())


class TheTemplate(NotificationTest):
    def test_tokens_are_filled(self):
        rendered = notifications.render(
            "{student_name} was marked ABSENT on {date}. - {school_name}",
            {"student_name": "Aarav Sharma", "date": "09/16/2026", "school_name": "Sunrise"},
        )

        self.assertEqual("Aarav Sharma was marked ABSENT on 09/16/2026. - Sunrise", rendered)

    def test_a_token_nobody_supplied_is_blanked_not_left_in_braces(self):
        # A reworded template must never leak "{student_name}" into a parent's
        # SMS.
        rendered = notifications.render("Hello {nobody_supplied_this}, welcome.", {})

        self.assertEqual("Hello , welcome.", rendered)
        self.assertNotIn("{", rendered)

    def test_a_school_uses_the_default_wording_until_it_overrides_one(self):
        self.assertEqual(
            MessageEvent.default_body(MessageEvent.ATTENDANCE_ABSENT),
            notifications.body_for(self.school.id, MessageEvent.ATTENDANCE_ABSENT),
        )

    def test_an_override_wins_while_it_is_active(self):
        MessageTemplate.objects.create(
            school_id=self.school.id,
            event=MessageEvent.ATTENDANCE_ABSENT,
            body="{student_name} is not in today.",
            is_active=True,
        )

        self.assertEqual(
            "{student_name} is not in today.",
            notifications.body_for(self.school.id, MessageEvent.ATTENDANCE_ABSENT),
        )

    def test_a_switched_off_override_falls_back_rather_than_sending_nothing(self):
        MessageTemplate.objects.create(
            school_id=self.school.id,
            event=MessageEvent.ATTENDANCE_ABSENT,
            body="{student_name} is not in today.",
            is_active=False,
        )

        self.assertEqual(
            MessageEvent.default_body(MessageEvent.ATTENDANCE_ABSENT),
            notifications.body_for(self.school.id, MessageEvent.ATTENDANCE_ABSENT),
        )

    def test_a_body_using_a_token_its_event_does_not_have_is_reported(self):
        unknown = notifications.unknown_tokens(
            "{student_name} rode {vehicle_name} on {date}",
            MessageEvent.tokens(MessageEvent.ATTENDANCE_ABSENT),
        )

        self.assertEqual(["vehicle_name"], unknown)


class WhatGetsRecorded(NotificationTest):
    def alert(self, event=MessageEvent.ATTENDANCE_ABSENT):
        return notifications.notify_guardian(event, self.student, {"class_name": "Grade 8 A"})

    def test_an_absence_is_recorded_and_queued(self):
        messages = self.alert()

        self.assertEqual(1, len(messages))
        self.assertEqual(MessageChannel.SMS, messages[0].channel, "guardians have no login")
        self.assertEqual(MessageStatus.QUEUED, messages[0].status)
        self.assertIn("Aarav Sharma", messages[0].body)
        self.assertEqual(1, QueuedJob.objects.filter(name=notifications.SEND_MESSAGE).count())

    def test_nothing_is_sent_during_the_call(self):
        # Recording and sending are separate so a provider being down cannot
        # roll back the register that caused the message.
        self.alert()

        self.assertEqual(MessageStatus.QUEUED, Message.objects.get().status)

    def test_a_switched_off_alert_is_not_logged_at_all(self):
        # Not "skipped" - the school never wanted it. One row per student per
        # day would bury the log.
        self.settings(attendance_alerts=AttendanceAlertMode.OFF)

        self.assertEqual([], self.alert())
        self.assertEqual(0, Message.objects.count())
        self.assertEqual(0, QueuedJob.objects.count())

    def test_absent_only_is_the_default_and_drops_the_present_alert(self):
        # A text every morning saying a child turned up is a text every parent
        # learns to ignore.
        self.assertEqual([], self.alert(MessageEvent.ATTENDANCE_PRESENT))
        self.assertEqual(1, len(self.alert(MessageEvent.ATTENDANCE_ABSENT)))

    def test_a_school_can_ask_for_both(self):
        self.settings(attendance_alerts=AttendanceAlertMode.PRESENT_AND_ABSENT)

        self.assertEqual(1, len(self.alert(MessageEvent.ATTENDANCE_PRESENT)))

    def test_sms_switched_off_records_nothing_for_an_sms_only_event(self):
        self.settings(sms_enabled=False)

        self.assertEqual([], self.alert())
        self.assertEqual(0, Message.objects.count())

    def test_a_guardian_with_no_number_is_logged_as_skipped_with_the_reason(self):
        # The school wanted to text this person and has no number for them.
        # That is a record to fix, so it belongs in the log.
        self.student.guardian_mobile = None
        self.student.save()

        messages = self.alert()

        self.assertEqual(MessageStatus.SKIPPED, messages[0].status)
        self.assertEqual("No mobile number on record.", messages[0].failure_reason)
        self.assertEqual(0, QueuedJob.objects.count(), "nothing to send")

    def test_a_staff_alert_goes_to_the_inbox_as_well_as_by_sms(self):
        teacher = factories.UserFactory(
            school=self.school, role=UserRole.TEACHER, mobile="+91 9000000001"
        )

        messages = notifications.notify_staff(
            MessageEvent.LEAVE_APPROVED,
            teacher,
            {"leave_type": "Casual", "start_date": "09/20/2026", "end_date": "09/21/2026"},
        )

        self.assertEqual(
            [MessageChannel.IN_APP, MessageChannel.SMS], [m.channel for m in messages]
        )

    def test_the_inbox_copy_survives_sms_being_switched_off(self):
        # Turning off SMS should not silently turn off the in-app inbox too.
        self.settings(sms_enabled=False)
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        messages = notifications.notify_staff(
            MessageEvent.LEAVE_APPROVED, teacher, {"leave_type": "Casual"}
        )

        self.assertEqual([MessageChannel.IN_APP], [m.channel for m in messages])

    def test_a_student_with_no_school_records_nothing(self):
        self.student.school_id = None

        self.assertEqual([], self.alert())


class SendingIt(NotificationTest):
    def test_the_worker_hands_it_to_the_gateway_and_marks_it_sent(self):
        notifications.notify_guardian(
            MessageEvent.ATTENDANCE_ABSENT, self.student, {"class_name": "Grade 8 A"}
        )

        result = queue.work()

        self.assertEqual({"done": 1, "failed": 0}, result)

        message = Message.objects.get()
        self.assertEqual(MessageStatus.SENT, message.status)
        self.assertIsNotNone(message.sent_at)

    def test_an_inbox_message_needs_no_gateway(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER, mobile=None)

        notifications.notify_staff(
            MessageEvent.LEAVE_APPROVED, teacher, {"leave_type": "Casual"}
        )
        queue.work()

        inbox = Message.objects.get(channel=MessageChannel.IN_APP)
        self.assertEqual(MessageStatus.SENT, inbox.status)

    def test_a_message_already_handled_is_left_alone(self):
        # Two workers overlapping, or a retry after the row was dealt with by
        # hand. Either way it must not be sent twice.
        notifications.notify_guardian(
            MessageEvent.ATTENDANCE_ABSENT, self.student, {"class_name": "Grade 8 A"}
        )
        Message.objects.update(status=MessageStatus.FAILED)

        queue.work()

        self.assertEqual(MessageStatus.FAILED, Message.objects.get().status)


class TheGateway(NotificationTest):
    def test_the_demo_gateway_is_honest_about_not_delivering(self):
        # The most dangerous adapter in the codebase would be one that claimed
        # otherwise: a school would read "Sent" and assume a parent was told.
        self.assertFalse(sms.gateway("log").delivers)
        self.assertEqual("Demo Gateway", sms.gateway("log").label)

    def test_an_unknown_gateway_falls_back_rather_than_crashing(self):
        # A school whose chosen provider has been removed from the build
        # should still have its messages recorded honestly.
        with self.assertLogs("school.sms", level="WARNING"):
            fallback = sms.gateway("a-provider-that-was-removed")

        self.assertEqual("log", fallback.name)

    def test_nothing_reaches_a_gateway_without_a_number(self):
        self.student.guardian_mobile = None
        self.student.save()

        notifications.notify_guardian(
            MessageEvent.ATTENDANCE_ABSENT, self.student, {"class_name": "Grade 8 A"}
        )

        self.assertEqual(MessageStatus.SKIPPED, Message.objects.get().status)


class TheEventCatalogue(TestCase):
    def test_every_event_has_wording_and_a_token_list(self):
        for event in MessageEvent.values:
            with self.subTest(event=event):
                body = MessageEvent.default_body(event)

                self.assertTrue(body)
                self.assertTrue(MessageEvent.tokens(event))

    def test_every_token_a_default_body_uses_is_one_the_event_provides(self):
        # The check that stops a default from leaking an empty placeholder
        # into a real message.
        for event in MessageEvent.values:
            with self.subTest(event=event):
                unknown = notifications.unknown_tokens(
                    MessageEvent.default_body(event), MessageEvent.tokens(event)
                )

                self.assertEqual([], unknown)

    def test_guardian_alerts_never_reach_an_inbox_and_staff_alerts_do(self):
        # Guardians have no login, so there is no inbox to put anything in.
        self.assertEqual(
            [MessageChannel.SMS, MessageChannel.WHATSAPP, MessageChannel.EMAIL],
            MessageEvent.channels(MessageEvent.ATTENDANCE_ABSENT),
        )
        self.assertIn(
            MessageChannel.IN_APP, MessageEvent.channels(MessageEvent.LEAVE_APPROVED)
        )


def section_in(school):
    year = factories.AcademicYearFactory(school=school)
    school_class = factories.SchoolClassFactory(academic_year=year, school=school)

    return factories.ClassSectionFactory(school_class=school_class)

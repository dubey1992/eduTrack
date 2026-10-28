"""Fee reminders (docs/fees.md, F5): the hourly send_fee_reminders job - who
is reminded, on which day, grouped how, said how, sent through what, and
never twice - and the hand-sent fee reminder filling itself in from what the
student really owes.

Same school, year and frozen clock as test_fees_dues.py: 2026-27, "now" is
15 July 2026, 11:30 in Kolkata. Besides Class 8's Tuition (due 10 April,
10 July, 10 October, 10 January) Class 8 has an Exam fee: "Unit" due
14 July - first overdue today - and "Term 1" due 18 July - three days off,
the default reminder.
"""

import datetime as dt
import io
from unittest import mock

from django.core.management import CommandError, call_command

from school import factories, notifications
from school.enums import StudentStatus
from school.fees.dues import FeeDueService
from school.fees.reminders import FeeReminderService, guardian_key
from school.models import (
    AuditLog,
    CommunicationSetting,
    FeeHead,
    FeeReminderLog,
    Message,
    ModuleSetting,
    QueuedJob,
    StudentFeeDue,
)

from .test_fees_receipts import ReceiptsTestCase

EXAM = [("Unit", dt.date(2026, 7, 14), "200.00"), ("Term 1", dt.date(2026, 7, 18), "500.00")]
NOTICES = "/api/v1/communication/notices"
MOBILE = "+91 98123 45678"


def at(moment: dt.datetime):
    return mock.patch("django.utils.timezone.now", return_value=moment)


class RemindersTestCase(ReceiptsTestCase):
    def setUp(self):
        super().setUp()
        self.aarav.guardian_mobile = MOBILE
        self.aarav.guardian_name = "Meera Shah"
        self.aarav.save()
        self.exam = FeeHead.objects.create(school=self.school, name="Exam")
        self.published(EXAM, school_class=self.class8, head=self.exam)

    def pupil(self, first_name, **fields):
        """A student added after the fees were published, and charged."""
        student = self.student(first_name, **fields)
        FeeDueService.sync_student(student, self.year)

        return student

    def settings_are(self, **values):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(settings=values)

    def run_job(self, *args) -> str:
        out = io.StringIO()
        call_command("send_fee_reminders", "--school", str(self.school.id), *args, stdout=out)

        return out.getvalue()

    def bodies(self) -> list[str]:
        return list(Message.objects.order_by("id").values_list("body", flat=True))


class WhoIsReminded(RemindersTestCase):
    def test_upcoming_exactly_n_days_ahead_and_overdue_on_the_first_overdue_day(self):
        self.run_job()

        upcoming, overdue = self.bodies()
        self.assertEqual(
            "Dear Meera Shah, a fee of INR 500.00 for Aarav Shah is due on 07/18/2026. "
            "Aarav Shah: Exam - Term 1 INR 500.00. Please pay at the school office. - Sunrise Public School",
            upcoming,
        )
        # The July tuition fell due on the 10th: not its first overdue day,
        # so it is not mentioned.
        self.assertEqual(
            "Dear Meera Shah, a fee of INR 200.00 for Aarav Shah is due on 07/14/2026. "
            "Now overdue. Aarav Shah: Exam - Unit INR 200.00. Please pay at the school office. - Sunrise Public School",
            overdue,
        )
        self.assertEqual(
            {("upcoming", dt.date(2026, 7, 15)), ("overdue", dt.date(2026, 7, 15))},
            set(FeeReminderLog.objects.values_list("kind", "reminder_date")),
        )

    def test_another_number_of_days_moves_the_upcoming_reminder(self):
        self.settings_are(reminder_days_before=2, remind_when_overdue=False)
        self.run_job()
        self.assertEqual([], self.bodies())  # nothing falls due on the 17th

        self.settings_are(reminder_days_before=3, remind_when_overdue=False)
        self.run_job()
        self.assertEqual(1, Message.objects.count())

    def test_the_next_day_the_same_due_is_not_overdue_for_the_first_time_any_more(self):
        self.settings_are(reminder_days_before=0, remind_when_overdue=True)

        with at(dt.datetime(2026, 7, 16, 6, 0, tzinfo=dt.timezone.utc)):
            self.run_job()

        self.assertEqual([], self.bodies())

    def test_zero_days_and_no_overdue_switch_every_reminder_off(self):
        self.settings_are(reminder_days_before=0, remind_when_overdue=False)

        out = self.run_job()

        self.assertIn("nothing sent (reminders switched off)", out)
        self.assertEqual((0, 0), (Message.objects.count(), FeeReminderLog.objects.count()))

    def test_zero_days_leaves_the_overdue_reminder_and_off_overdue_leaves_the_upcoming_one(self):
        self.settings_are(reminder_days_before=0, remind_when_overdue=True)
        self.run_job()
        self.assertEqual(["overdue"], list(FeeReminderLog.objects.values_list("kind", flat=True)))

        FeeReminderLog.objects.all().delete()
        Message.objects.all().delete()
        self.settings_are(reminder_days_before=3, remind_when_overdue=False)
        self.run_job()
        self.assertEqual(["upcoming"], list(FeeReminderLog.objects.values_list("kind", flat=True)))

    def test_an_inactive_student_and_a_due_a_discount_covers_are_never_reminded(self):
        diya = self.pupil("Diya", last_name="Rao", guardian_mobile="9000000001")
        kiran = self.pupil("Kiran", last_name="Das", guardian_mobile="9000000002")
        self.assertTrue(StudentFeeDue.objects.filter(student=diya, label="Exam - Term 1").exists())
        # Straight to the table, so her dues stay owed: only her status
        # keeps her out.
        diya.status = StudentStatus.INACTIVE
        diya.save()
        response = self.as_user(self.accountant).post("/api/v1/fees/concessions", {
            "student_id": kiran.id, "academic_year_id": self.year.id, "fee_head_id": self.exam.id,
            "kind": "percent", "value": "100", "reason": "Scholarship",
        }, format="json")
        self.assertEqual(201, response.status_code, response.data)

        self.run_job()

        self.assertEqual({"Aarav Shah"}, set(Message.objects.values_list("student_name", flat=True)))

    def test_a_paid_due_is_not_reminded(self):
        self.paid(amount="500.00", allocations=[{"due_id": self.due("Exam - Term 1").id, "amount": "500.00"}])

        self.run_job()

        self.assertEqual(["overdue"], list(FeeReminderLog.objects.values_list("kind", flat=True)))

    def test_the_day_is_the_schools_even_when_utc_is_still_on_yesterday(self):
        # 20:00 UTC on the 14th is 01:30 on the 15th in Kolkata: the Unit
        # fee (due the 14th) is overdue for the first time at the school.
        with at(dt.datetime(2026, 7, 14, 20, 0, tzinfo=dt.timezone.utc)):
            self.run_job()

        self.assertEqual(
            [("overdue", dt.date(2026, 7, 15)), ("upcoming", dt.date(2026, 7, 15))],
            sorted(FeeReminderLog.objects.values_list("kind", "reminder_date")),
        )


class OneMessagePerGuardian(RemindersTestCase):
    def test_siblings_sharing_a_guardians_mobile_get_one_message_naming_both_and_the_total(self):
        # The same number, written another way.
        self.pupil("Diya", last_name="Shah", guardian_mobile="919812345678", guardian_name="Meera Shah")
        self.pupil("Kiran", last_name="Das", guardian_mobile="9000000002", guardian_name="Ravi Das")
        self.settings_are(reminder_days_before=3, remind_when_overdue=False)

        self.run_job()

        shah, das = sorted(self.bodies())
        self.assertEqual(
            "Dear Meera Shah, a fee of INR 1,000.00 for Aarav Shah and Diya Shah is due on 07/18/2026. "
            "Aarav Shah: Exam - Term 1 INR 500.00. Diya Shah: Exam - Term 1 INR 500.00. "
            "Please pay at the school office. - Sunrise Public School",
            shah,
        )
        self.assertIn("Kiran Das: Exam - Term 1 INR 500.00.", das)
        log = FeeReminderLog.objects.get(guardian_key="m:919812345678")
        self.assertEqual(2, log.dues_count)
        self.assertEqual(2, len(log.student_ids.split(",")))

    def test_every_due_left_to_pay_is_listed_with_what_is_left_on_it(self):
        self.paid(amount="150.00", allocations=[{"due_id": self.due("Exam - Term 1").id, "amount": "150.00"}])
        self.settings_are(reminder_days_before=3, remind_when_overdue=False)

        self.run_job()

        self.assertIn("a fee of INR 350.00", self.bodies()[0])
        self.assertIn("Aarav Shah: Exam - Term 1 INR 350.00.", self.bodies()[0])

    def test_the_grouping_key_is_the_mobile_then_the_email_then_the_student(self):
        student = factories.StudentFactory(school=self.school, guardian_mobile=" +91-98123 45678 ")
        self.assertEqual("m:919812345678", guardian_key(student))
        student.guardian_mobile, student.guardian_email = None, " Meera@Example.com "
        self.assertEqual("e:meera@example.com", guardian_key(student))
        student.guardian_email = ""
        self.assertEqual(f"s:{student.id}", guardian_key(student))
        student.guardian_email = "x" * 200 + "@example.com"
        self.assertLessEqual(len(guardian_key(student)), 120)


class NeverTwice(RemindersTestCase):
    def test_a_second_run_the_same_day_sends_nothing(self):
        self.run_job()
        first = Message.objects.count()

        with at(dt.datetime(2026, 7, 15, 12, 0, tzinfo=dt.timezone.utc)):
            out = self.run_job()

        self.assertEqual(2, first)
        self.assertEqual(first, Message.objects.count())
        self.assertEqual(2, FeeReminderLog.objects.count())
        self.assertIn("2 already reminded today", out)

    def test_the_log_refuses_a_second_reminder_of_one_kind_on_one_day(self):
        self.run_job()
        reminders = FeeReminderService.send(self.school.id)

        self.assertEqual(0, reminders.guardians)
        self.assertEqual(2, reminders.already_sent)

    def test_one_audit_row_per_school_per_run_that_reminded_anybody(self):
        self.run_job()
        self.run_job()

        entry = AuditLog.objects.get(action="fee_reminders.sent")
        self.assertEqual(self.school.id, entry.school_id)
        self.assertEqual(
            {"upcoming": 1, "overdue": 1, "students": 1, "dues": 2, "messages": 2, "date": "2026-07-15",
             "upcoming_due_date": "2026-07-18", "overdue_due_date": "2026-07-14"},
            entry.new_values,
        )


class ThroughCommunication(RemindersTestCase):
    def test_messages_are_recorded_and_left_to_the_queue(self):
        self.run_job()

        messages = list(Message.objects.order_by("id"))
        self.assertEqual({("fee.reminder", "fee", "sms", "queued", "Fee reminder")},
                         {(m.event, m.category, m.channel, m.status, m.subject) for m in messages})
        self.assertEqual(
            sorted(m.id for m in messages),
            sorted(job.payload["message_id"] for job in QueuedJob.objects.filter(name="send_message")),
        )

    def test_with_communication_switched_off_nothing_is_sent_and_nothing_logged(self):
        factories.ModuleSettingFactory(school=self.school, module="communication", school_enabled=False)

        out = self.run_job()

        self.assertIn("communication module off", out)
        self.assertEqual((0, 0, 0), (Message.objects.count(), FeeReminderLog.objects.count(),
                                     QueuedJob.objects.filter(name="send_message").count()))

    def test_with_fees_switched_off_nothing_happens(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)

        out = self.run_job()

        self.assertIn("fees module off", out)
        self.assertEqual((0, 0), (Message.objects.count(), FeeReminderLog.objects.count()))

    def test_a_guardian_with_no_number_is_logged_as_skipped_and_reminded_once(self):
        self.aarav.guardian_mobile = None
        self.aarav.save()

        self.run_job()
        self.run_job()

        self.assertEqual({"skipped"}, set(Message.objects.values_list("status", flat=True)))
        self.assertEqual(2, Message.objects.count())

    def test_email_goes_too_when_the_school_has_it_on(self):
        CommunicationSetting.objects.create(school=self.school, **{**notifications.DEFAULTS, "email_enabled": True})
        self.aarav.guardian_email = "meera@example.com"
        self.aarav.save()
        self.settings_are(reminder_days_before=3, remind_when_overdue=False)

        self.run_job()

        self.assertEqual({"sms", "email"}, set(Message.objects.values_list("channel", flat=True)))

    def test_a_dry_run_says_what_it_would_do_and_writes_nothing(self):
        out = self.run_job("--dry-run")

        self.assertIn("1 upcoming (due 07/18/2026) and 1 overdue (due 07/14/2026)", out)
        self.assertIn("dry run, nothing sent", out)
        self.assertEqual((0, 0, 0), (Message.objects.count(), FeeReminderLog.objects.count(),
                                     AuditLog.objects.filter(action="fee_reminders.sent").count()))

    def test_every_school_with_fees_on_and_an_unknown_school(self):
        out = io.StringIO()
        call_command("send_fee_reminders", stdout=out)
        self.assertIn(f"School {self.school.id}:", out.getvalue())

        with self.assertRaises(CommandError):
            call_command("send_fee_reminders", "--school", "999999", stdout=io.StringIO())


class HandSentReminder(RemindersTestCase):
    def send(self, **fields):
        body = {"kind": "fee_reminder", "audience_type": "student", "audience_id": self.aarav.id,
                "channels": ["sms"], **fields}

        return self.as_user(self.admin).post(NOTICES, body, format="json")

    def test_without_an_amount_or_date_it_takes_what_the_student_owes_and_the_earliest_date(self):
        # Owed now: April and July tuition, the Unit and Term 1 exam fees,
        # and the two tuition installments still to come - 4,700 in all,
        # the earliest still owed due on 10 April.
        response = self.send()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(
            "Dear Meera Shah, a fee of INR 4,700.00 for Aarav Shah is due on 04/10/2026. "
            "Please pay at the school office. - Sunrise Public School",
            Message.objects.get().body,
        )

    def test_what_the_sender_typed_is_kept(self):
        response = self.send(amount="999", due_date="2026-08-01")

        self.assertEqual(201, response.status_code, response.data)
        self.assertIn("a fee of INR 999.00 for Aarav Shah is due on 08/01/2026", Message.objects.get().body)

    def test_only_the_missing_field_is_filled(self):
        response = self.send(amount="250")

        self.assertEqual(201, response.status_code, response.data)
        self.assertIn("a fee of INR 250.00 for Aarav Shah is due on 04/10/2026", Message.objects.get().body)

    def test_a_student_who_owes_nothing_still_needs_both(self):
        StudentFeeDue.objects.filter(student=self.aarav).update(status="waived")

        response = self.send()

        self.assertEqual(422, response.status_code)
        self.assertEqual({"amount", "due_date"}, set(response.data["details"]["errors"]))

    def test_without_fee_management_it_needs_both_as_before(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").update(school_enabled=False)

        response = self.send()

        self.assertEqual(422, response.status_code)
        self.assertEqual({"amount", "due_date"}, set(response.data["details"]["errors"]))

    def test_a_group_audience_still_needs_both(self):
        response = self.send(audience_type="class_section", audience_id=self.section8.id)

        self.assertEqual(422, response.status_code)
        self.assertEqual({"amount", "due_date"}, set(response.data["details"]["errors"]))

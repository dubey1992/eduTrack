"""Reminders for staff from the school's own day (docs/mobile-apps-review.md,
5.1, decided 2026-11-18): off for live schools until switched on, the inbox
and push only, at most once a day each.

The day is the Today tests' Monday, 26 October 2026, in Kolkata: periods
9:00-9:45, 10:00-10:45 and 11:00-11:45. The teacher is class teacher of 8 A
and teaches periods 1 and 3.
"""

import datetime as dt

from django.utils.timezone import now as real_now

from school import factories, push, staff_reminders
from school.enums import MessageChannel, MessageEvent, SchoolStatus, UserRole
from school.models import Attendance, Holiday, Message, ModuleSetting, School, StaffAttendance
from school.tests.test_schools_api import a_payload
from school.tests.test_today_api import UTC, TodayTestCase, at

MONDAY = dt.date(2026, 10, 26)


def ist(hour, minute=0):
    """A moment on that Monday, Kolkata time."""
    return dt.datetime(2026, 10, 26, hour, minute, tzinfo=dt.timezone(dt.timedelta(hours=5, minutes=30))).astimezone(UTC)


class StaffRemindersCase(TodayTestCase):
    def switch_on(self, *keys, school=None):
        modules = {"remind_register": "attendance", "remind_check_in": "staff_attendance",
                   "remind_reports_owed": "teaching_reports"}
        for key in keys:
            factories.ModuleSettingFactory(school=school or self.school, module=modules[key], settings={key: True})

    def run_at(self, instant):
        with at(instant):
            return staff_reminders.send(at=instant)

    def reminders(self, event, user=None):
        found = Message.objects.filter(event=event)
        if user is not None:
            found = found.filter(user_id=user.id)

        return list(found)


class Switches(StaffRemindersCase):
    def test_a_school_already_live_gets_none_until_an_admin_switches_them_on(self):
        factories.StaffProfileFactory(school=self.school, user=self.teacher)

        self.assertEqual(0, self.run_at(ist(12)))
        self.assertFalse(Message.objects.exists())

    def test_a_new_school_starts_with_all_three_on(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)
        response = self.client_for(root).post("/api/v1/schools", a_payload(name="New School"), format="json")
        self.assertEqual(201, response.status_code, response.data)
        school = School.objects.get(pk=response.data["id"])

        self.assertEqual(
            {("attendance", "remind_register"), ("staff_attendance", "remind_check_in"),
             ("teaching_reports", "remind_reports_owed")},
            {(row.module, next(iter(row.settings))) for row in ModuleSetting.objects.filter(school=school)},
        )
        for event in staff_reminders.SWITCHES:
            self.assertTrue(staff_reminders.switched_on(school.id, event), event)

    def test_another_schools_switch_does_not_reach_this_school(self):
        self.switch_on("remind_register", school=factories.SchoolFactory(timezone="Asia/Kolkata"))

        self.run_at(ist(10, 15))

        self.assertEqual([], self.reminders(MessageEvent.REGISTER_REMINDER))

    def test_an_inactive_school_is_left_alone(self):
        self.switch_on("remind_register")
        self.school.status = SchoolStatus.INACTIVE
        self.school.save()

        self.assertEqual(0, self.run_at(ist(10, 15)))


class RegisterNotTaken(StaffRemindersCase):
    def setUp(self):
        super().setUp()
        self.switch_on("remind_register")

    def test_the_class_teacher_hears_once_the_first_period_is_over_in_the_app_only(self):
        self.run_at(ist(10, 15))

        reminder = self.reminders(MessageEvent.REGISTER_REMINDER, self.teacher)
        self.assertEqual(1, len(reminder))
        self.assertEqual(MessageChannel.IN_APP, reminder[0].channel)
        self.assertEqual("Today's register for Grade 8 A is not taken yet.", reminder[0].body)
        self.assertEqual("/today", push.route_for(reminder[0]))
        self.assertEqual([], self.reminders(MessageEvent.REGISTER_REMINDER, self.other), "not a class teacher")

    def test_not_before_the_first_period_ends(self):
        self.run_at(ist(9, 30))

        self.assertEqual([], self.reminders(MessageEvent.REGISTER_REMINDER))

    def test_once_a_day_however_often_cron_runs(self):
        self.run_at(ist(10, 15))
        self.run_at(ist(10, 30))
        self.run_at(ist(14))

        self.assertEqual(1, len(self.reminders(MessageEvent.REGISTER_REMINDER, self.teacher)))

    def test_a_register_already_taken_is_not_reminded(self):
        student = factories.StudentFactory(school=self.school, class_section=self.eight_a)
        Attendance.objects.create(
            school_id=self.school.id, academic_year_id=self.year.id, class_section_id=self.eight_a.id,
            student=student, attendance_date=MONDAY, status="present", created_at=real_now(), updated_at=real_now(),
        )

        self.run_at(ist(10, 15))

        self.assertEqual([], self.reminders(MessageEvent.REGISTER_REMINDER))

    def test_nothing_on_a_holiday_or_a_closed_day(self):
        Holiday.objects.create(
            school_id=self.school.id, name="Diwali", type="religious", start_date=MONDAY, end_date=MONDAY,
            created_at=real_now(), updated_at=real_now(),
        )
        self.run_at(ist(10, 15))
        # Sunday, closed by the school's week.
        sunday = dt.datetime(2026, 10, 25, 4, 45, tzinfo=UTC)
        self.run_at(sunday)

        self.assertEqual([], self.reminders(MessageEvent.REGISTER_REMINDER))

    def test_a_teacher_on_leave_is_not_reminded(self):
        profile = factories.StaffProfileFactory(school=self.school, user=self.teacher)
        factories.StaffLeaveFactory(staff_profile=profile, status="approved", start_date=MONDAY, end_date=MONDAY)

        self.run_at(ist(10, 15))

        self.assertEqual([], self.reminders(MessageEvent.REGISTER_REMINDER))


class ReportsOwed(StaffRemindersCase):
    def setUp(self):
        super().setUp()
        self.switch_on("remind_reports_owed")

    def test_once_the_last_period_has_ended_with_how_many(self):
        self.run_at(ist(11))
        self.assertEqual([], self.reminders(MessageEvent.REPORTS_REMINDER), "the day is not over")

        self.run_at(ist(12))

        reminder = self.reminders(MessageEvent.REPORTS_REMINDER, self.teacher)
        self.assertEqual(["You have 2 teaching reports to file for today."], [m.body for m in reminder])

    def test_a_teacher_who_filed_everything_hears_nothing(self):
        for entry in (self.first, self.third):
            factories.DailyTeachingReportFactory(timetable_entry=entry, teacher=self.teacher, report_date=MONDAY)

        self.run_at(ist(12))

        self.assertEqual([], self.reminders(MessageEvent.REPORTS_REMINDER, self.teacher))

    def test_one_left_says_one(self):
        factories.DailyTeachingReportFactory(timetable_entry=self.first, teacher=self.teacher, report_date=MONDAY)

        self.run_at(ist(12))

        self.assertEqual(
            "You have a teaching report to file for today.",
            self.reminders(MessageEvent.REPORTS_REMINDER, self.teacher)[0].body,
        )


class NotCheckedIn(StaffRemindersCase):
    def setUp(self):
        super().setUp()
        self.switch_on("remind_check_in")
        self.clerk = factories.UserFactory(school=self.school, role=UserRole.STAFF)
        self.clerk_profile = factories.StaffProfileFactory(school=self.school, user=self.clerk)

    def test_thirty_minutes_into_the_first_period_and_not_before(self):
        self.run_at(ist(9, 20))
        self.assertEqual([], self.reminders(MessageEvent.CHECK_IN_REMINDER))

        self.run_at(ist(9, 30))

        self.assertEqual(1, len(self.reminders(MessageEvent.CHECK_IN_REMINDER, self.clerk)))

    def test_anyone_already_marked_is_left_alone(self):
        StaffAttendance.objects.create(
            school_id=self.school.id, staff_profile=self.clerk_profile, attendance_date=MONDAY, status="present",
            created_at=real_now(), updated_at=real_now(),
        )

        self.run_at(ist(10))

        self.assertEqual([], self.reminders(MessageEvent.CHECK_IN_REMINDER, self.clerk))

    def test_bus_crew_and_people_on_leave_are_not_reminded(self):
        driver = factories.UserFactory(school=self.school, role=UserRole.DRIVER)
        factories.StaffProfileFactory(school=self.school, user=driver)
        factories.StaffLeaveFactory(
            staff_profile=self.clerk_profile, status="approved", start_date=MONDAY, end_date=MONDAY
        )

        self.run_at(ist(10))

        self.assertEqual([], self.reminders(MessageEvent.CHECK_IN_REMINDER))

    def test_a_school_that_marks_staff_in_the_office_sends_none(self):
        row = ModuleSetting.objects.get(school=self.school, module="staff_attendance")
        row.settings = {**row.settings, "app_check_in": False}
        row.save()

        self.run_at(ist(10))

        self.assertEqual([], self.reminders(MessageEvent.CHECK_IN_REMINDER))

    def test_not_once_the_school_day_is_over(self):
        self.run_at(ist(12))

        self.assertEqual([], self.reminders(MessageEvent.CHECK_IN_REMINDER))

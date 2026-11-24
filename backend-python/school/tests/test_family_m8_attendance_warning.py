"""Attendance warnings to parents (docs/mobile-apps-review.md, M8, 5.4):
once per drop below the school's early-warning line, in the Family app, with
the figure - the same figure the office's Early Warning list shows.
"""

import datetime as dt

from school import attendance_warnings
from school.clock import SchoolClock
from school.enums import AttendanceStatus, MessageEvent
from school.models import Attendance, AttendanceWarning, Message, ModuleSetting

from . import test_family_f1_api as f1

FAMILY = f1.FAMILY


class WarningTest(f1.FamilyAppTest):
    def evening(self, hour=18, minute=30):
        clock = SchoolClock.for_school(self.school)
        return clock.now().replace(hour=hour, minute=minute, second=0, microsecond=0)

    def marked(self, present: int, absent: int):
        """[present] then [absent] school days, ending today."""
        days = present + absent
        for offset in range(days):
            day = self.today() - dt.timedelta(days=days - 1 - offset)
            self.mark(self.child, day, AttendanceStatus.PRESENT if offset < present else AttendanceStatus.ABSENT)

    def run_job(self, **kwargs):
        return attendance_warnings.check(at=self.evening(**kwargs), school_id=self.school.id)

    def sent(self):
        return Message.objects.filter(event=MessageEvent.ATTENDANCE_BELOW_LINE, student=self.child)


class BelowTheLine(WarningTest):
    def test_below_the_line_the_family_is_told_with_the_figure(self):
        self.marked(present=8, absent=4)

        self.assertEqual(1, self.run_job())

        message = self.sent().get()
        self.assertIn("attendance is 66.7% over the last 30 school days, below the school's 75% line", message.body)
        row = AttendanceWarning.objects.get(student=self.child)
        self.assertEqual((66.7, 75, None), (float(row.rate), row.line, row.cleared_at))

    def test_at_or_above_the_line_nothing_is_sent(self):
        self.marked(present=9, absent=3)  # 75% exactly

        self.assertEqual(0, self.run_job())
        self.assertFalse(self.sent().exists())

    def test_too_few_marked_days_says_nothing(self):
        self.marked(present=2, absent=5)

        self.assertEqual(0, self.run_job())

    def test_not_before_six(self):
        self.marked(present=8, absent=4)

        self.assertEqual(0, self.run_job(hour=17, minute=45))

    def test_the_schools_own_line_is_used(self):
        ModuleSetting.objects.update_or_create(
            school=self.school, module="reports",
            defaults={"platform_enabled": True, "school_enabled": True,
                      "settings": {"early_warning_attendance_below": 60}},
        )
        self.marked(present=8, absent=4)  # 66.7%, above a 60% line

        self.assertEqual(0, self.run_job())


class OncePerDrop(WarningTest):
    def test_once_however_often_the_job_runs(self):
        self.marked(present=8, absent=4)

        for minute in (0, 15, 30, 45):
            self.run_job(hour=19, minute=minute)

        self.assertEqual(1, self.sent().count())

    def test_back_above_the_line_closes_it_quietly_and_a_new_drop_is_told_again(self):
        self.marked(present=8, absent=4)
        self.run_job()

        # The absences were corrected: back up to 100%.
        Attendance.objects.filter(student=self.child).update(status=AttendanceStatus.PRESENT)
        self.run_job(hour=19)
        self.assertIsNotNone(AttendanceWarning.objects.get(student=self.child).cleared_at)
        self.assertEqual(1, self.sent().count())

        # And down again.
        Attendance.objects.filter(student=self.child, attendance_date__gte=self.today() - dt.timedelta(days=3)).update(
            status=AttendanceStatus.ABSENT
        )
        self.run_job(hour=20)

        self.assertEqual(2, self.sent().count())
        self.assertEqual(2, AttendanceWarning.objects.filter(student=self.child).count())


class OnTheAttendanceScreen(WarningTest):
    def month(self):
        today = self.today()
        response = self.parent.get(
            f"{FAMILY}/children/{self.child.id}/attendance", {"month": f"{today.year}-{today.month:02d}"}
        )
        self.assertEqual(200, response.status_code, response.data)
        return response.data

    def test_the_warning_shows_while_it_stands(self):
        self.marked(present=8, absent=4)
        self.run_job()

        self.assertEqual({"rate": "66.7", "line": 75, "days": 30}, self.month()["below_line"])

    def test_no_warning_none_shown(self):
        self.assertIsNone(self.month()["below_line"])

    def test_a_parent_who_turned_attendance_alerts_off_is_not_told(self):
        self.parent.patch(f"{FAMILY}/notification-settings", {"attendance": False}, format="json")
        self.marked(present=8, absent=4)

        self.run_job()

        self.assertFalse(self.sent().exists())
        # The screen still says it: the switch is about messages.
        self.assertIsNotNone(self.month()["below_line"])

"""The parent's screens in the Family app (docs/parent-student-app.md, F1).

What this file guards that a quick read would not:

- **Only the caller's own children.** Another family's child, a child at
  another school and a child who has left are all a 404, never a 403, so
  the answer does not even confirm the child exists.
- **The percentage counts working days only** (the Phase 18 rule): a
  holiday and a closed weekday are neither present nor absent.
- **The school's messages reach the app as well as the phone.** A parent
  with the Family app gets an in-app copy of what the school texts them,
  addressed to them; their own switches decide each kind except an
  emergency; and a whole-school notice arrives once however many children
  they have there. A school with SMS off still reaches the app.
- **The module switch stops the app.** Off, every screen answers
  MODULE_DISABLED.
"""

import datetime as dt
from decimal import Decimal

from django.utils import timezone

from school import factories, notifications
from school.clock import SchoolClock
from school.enums import AttendanceStatus, MessageChannel, MessageEvent, UserRole
from school.models import (
    Announcement,
    Attendance,
    DeviceToken,
    FamilyNotificationSetting,
    FeeHead,
    Holiday,
    Message,
    ModuleSetting,
    StudentFeeDue,
    StudentTransportAssignment,
    TransportTrip,
    TransportTripRider,
    User,
)
from school.tests.test_family_api import MOBILE, FamilyTestCase

FAMILY = "/api/v1/family"


class FamilyAppTest(FamilyTestCase):
    def setUp(self):
        super().setUp()
        # Every day a school day, so "today" works whatever day the suite runs.
        self.school.working_days = "1111111"
        self.school.save(update_fields=["working_days"])
        self.year = factories.AcademicYearFactory(
            school=self.school, start_date=self.today() - dt.timedelta(days=60),
            end_date=self.today() + dt.timedelta(days=200),
        )
        token, _ = self.register()
        self.parent = self.as_token(token)
        self.parent_user = User.objects.get(role=UserRole.PARENT, school=self.school)

    def today(self) -> dt.date:
        return SchoolClock.for_school(self.school).now().date()

    def mark(self, student, day, status, remarks=None):
        now = timezone.now()
        return Attendance.objects.create(
            school=self.school, academic_year=self.year, class_section=student.class_section, student=student,
            attendance_date=day, status=status, remarks=remarks, marked_by=self.admin, created_at=now,
            updated_at=now,
        )

    def other_family_child(self):
        return self.student("Kabir", "+91 99999 11111", guardian_name="Someone Else")


class AParentSeesToday(FamilyAppTest):
    def test_today_says_the_child_is_in_school(self):
        self.mark(self.child, self.today(), AttendanceStatus.PRESENT)

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/today")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(self.today().isoformat(), response.data["date"])
        self.assertTrue(response.data["school_day"]["is_open"])
        self.assertEqual("present", response.data["attendance"]["status"])

    def test_an_unmarked_register_says_not_marked_yet(self):
        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/today")

        self.assertEqual("not_marked", response.data["attendance"]["status"])

    def test_a_holiday_closes_the_day(self):
        Holiday.objects.create(school=self.school, name="Diwali", type="religious", start_date=self.today(),
                               end_date=self.today(), created_at=timezone.now(), updated_at=timezone.now())

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/today")

        self.assertFalse(response.data["school_day"]["is_open"])
        self.assertEqual("Diwali", response.data["school_day"]["holiday"]["name"])
        self.assertIsNone(response.data["attendance"])

    def test_the_next_fee_due_is_the_earliest_still_owed(self):
        head = FeeHead.objects.create(school=self.school, name="Tuition", created_at=timezone.now(),
                                      updated_at=timezone.now())

        def due(label, days, amount, paid="0"):
            return StudentFeeDue.objects.create(
                school=self.school, student=self.child, academic_year=self.year, fee_head=head, label=label,
                due_date=self.today() + dt.timedelta(days=days), amount=Decimal(amount), paid_amount=Decimal(paid),
                currency_code="INR", status="paid" if paid == amount else "pending",
                created_at=timezone.now(), updated_at=timezone.now(),
            )

        due("Term 1", -30, "5000.00", paid="5000.00")
        due("Term 2", 10, "5000.00", paid="1500.00")
        due("Term 3", 90, "5000.00")

        fee = self.parent.get(f"{FAMILY}/children/{self.child.id}/today").data["fee"]

        self.assertEqual(("Term 2", "3500.00", "INR", False), (fee["label"], fee["amount"], fee["currency_code"],
                                                               fee["is_overdue"]))

    def test_the_bus_shows_the_childs_own_trip(self):
        vehicle = factories.VehicleFactory(school=self.school)
        driver = factories.DriverFactory(school=self.school)
        route = factories.TransportRouteFactory(school=self.school, vehicle=vehicle, driver=driver)
        stop = factories.TransportStopFactory(route=route, name="Gate 2", pickup_time=dt.time(7, 30))
        StudentTransportAssignment.objects.create(school=self.school, student=self.child, route=route,
                                                  transport_stop=stop, created_at=timezone.now(),
                                                  updated_at=timezone.now())
        trip = TransportTrip.objects.create(school=self.school, route=route, vehicle=vehicle, driver=driver,
                                            started_by=self.admin, trip_date=self.today(),
                                            direction="pickup", status="in_progress", started_at=timezone.now(),
                                            created_at=timezone.now(), updated_at=timezone.now())
        TransportTripRider.objects.create(trip=trip, student=self.child, stop=stop, stop_name=stop.name,
                                          stop_sequence_number=1, status="boarded", boarded_at=timezone.now(),
                                          created_at=timezone.now(), updated_at=timezone.now())

        bus = self.parent.get(f"{FAMILY}/children/{self.child.id}/today").data["bus"]

        self.assertEqual(("Gate 2", "07:30"), (bus["stop"], bus["pickup_time"]))
        [today_trip] = bus["trips"]
        self.assertEqual(("pickup", "boarded"), (today_trip["direction"], today_trip["rider_status"]))
        self.assertIsNotNone(today_trip["boarded_at"])

    def test_a_child_without_transport_has_no_bus(self):
        self.assertIsNone(self.parent.get(f"{FAMILY}/children/{self.child.id}/today").data["bus"])


class AParentSeesOnlyTheirOwnChildren(FamilyAppTest):
    def test_another_familys_child_is_not_found(self):
        stranger = self.other_family_child()

        for path in ("today", "attendance"):
            with self.subTest(path=path):
                response = self.parent.get(f"{FAMILY}/children/{stranger.id}/{path}")
                self.assertEqual(404, response.status_code)

    def test_a_child_at_another_school_is_not_found(self):
        elsewhere = factories.StudentFactory(guardian_mobile=MOBILE)

        self.assertEqual(404, self.parent.get(f"{FAMILY}/children/{elsewhere.id}/today").status_code)

    def test_a_child_who_has_left_is_not_found(self):
        self.child.status = "inactive"
        self.child.save(update_fields=["status"])

        self.assertEqual(404, self.parent.get(f"{FAMILY}/children/{self.child.id}/today").status_code)

    def test_a_staff_session_is_refused(self):
        response = self.as_user(self.admin).get(f"{FAMILY}/children/{self.child.id}/today")

        self.assertEqual(403, response.status_code)
        self.assertEqual("NOT_A_FAMILY_ACCOUNT", response.data["code"])

    def test_without_a_session_nothing_is_shown(self):
        from rest_framework.test import APIClient

        self.assertEqual(401, APIClient().get(f"{FAMILY}/children/{self.child.id}/today").status_code)

    def test_the_module_switched_off_stops_every_screen(self):
        ModuleSetting.objects.filter(school=self.school, module="family_app").update(school_enabled=False)

        for path in (f"children/{self.child.id}/today", f"children/{self.child.id}/attendance", "calendar",
                     "notices", "notification-settings"):
            with self.subTest(path=path):
                response = self.parent.get(f"{FAMILY}/{path}")
                self.assertEqual(403, response.status_code)
                self.assertEqual("MODULE_DISABLED", response.data["code"])


class AParentSeesTheAttendanceCalendar(FamilyAppTest):
    def test_each_day_has_its_kind_and_an_absence_its_reason(self):
        today = self.today()
        self.mark(self.child, today, AttendanceStatus.ABSENT, remarks="Fever")

        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/attendance",
                                   {"month": today.strftime("%Y-%m")})

        self.assertEqual(200, response.status_code, response.data)
        day = next(d for d in response.data["days"] if d["date"] == today.isoformat())
        self.assertEqual(("absent", "Fever"), (day["kind"], day["remarks"]))

    def test_the_rate_counts_working_days_only(self):
        self.school.working_days = "1111100"
        self.school.save(update_fields=["working_days"])
        # A week of last month that has no holiday in it.
        start = (self.today().replace(day=1) - dt.timedelta(days=20))
        monday = start - dt.timedelta(days=start.weekday())
        for offset in range(5):
            self.mark(self.child, monday + dt.timedelta(days=offset),
                      AttendanceStatus.ABSENT if offset == 4 else AttendanceStatus.PRESENT)
        Holiday.objects.create(school=self.school, name="Founders' Day", type="school_event",
                               start_date=monday + dt.timedelta(days=2), end_date=monday + dt.timedelta(days=2),
                               created_at=timezone.now(), updated_at=timezone.now())

        data = self.parent.get(f"{FAMILY}/children/{self.child.id}/attendance",
                               {"month": monday.strftime("%Y-%m")}).data
        days = {d["date"]: d for d in data["days"]}

        self.assertEqual("holiday", days[(monday + dt.timedelta(days=2)).isoformat()]["kind"])
        self.assertEqual("closed", days[(monday + dt.timedelta(days=5)).isoformat()]["kind"])
        # Founders' Day neither counts as present nor as a working day.
        week = [monday + dt.timedelta(days=offset) for offset in range(5)]
        marked = [days[d.isoformat()]["kind"] for d in week if d.isoformat() in days]
        self.assertNotIn("present", [days[(monday + dt.timedelta(days=2)).isoformat()]["kind"]])
        self.assertIn("absent", marked)

    def test_a_badly_written_month_is_refused(self):
        response = self.parent.get(f"{FAMILY}/children/{self.child.id}/attendance", {"month": "Nov 2026"})

        self.assertEqual(422, response.status_code)
        self.assertIn("month", response.data["details"]["errors"])

    def test_the_year_so_far_has_a_rate(self):
        self.mark(self.child, self.today(), AttendanceStatus.PRESENT)

        summary = self.parent.get(f"{FAMILY}/children/{self.child.id}/attendance").data["year_summary"]

        self.assertEqual(self.year.name, summary["label"])
        self.assertEqual(1, summary["present"])
        self.assertIsNotNone(summary["rate"])


class AParentSeesTheSchoolCalendar(FamilyAppTest):
    def test_holidays_and_closed_weekdays(self):
        self.school.working_days = "1111100"
        self.school.save(update_fields=["working_days"])
        day = self.today() + dt.timedelta(days=3)
        Holiday.objects.create(school=self.school, name="Diwali", type="religious", start_date=day, end_date=day,
                               created_at=timezone.now(), updated_at=timezone.now())

        data = self.parent.get(f"{FAMILY}/calendar", {"month": day.strftime("%Y-%m")}).data

        self.assertEqual(["saturday", "sunday"], data["closed_weekdays"])
        self.assertEqual(["Diwali"], [holiday["name"] for holiday in data["holidays"]])
        self.assertEqual("Diwali", data["upcoming"][0]["name"])

    def test_another_schools_holidays_are_not_shown(self):
        day = self.today() + dt.timedelta(days=3)
        Holiday.objects.create(school=factories.SchoolFactory(), name="Elsewhere", type="religious",
                               start_date=day, end_date=day, created_at=timezone.now(), updated_at=timezone.now())

        data = self.parent.get(f"{FAMILY}/calendar", {"month": day.strftime("%Y-%m")}).data

        self.assertEqual([], data["holidays"])


class TheSchoolsMessagesReachTheApp(FamilyAppTest):
    def absent(self, student=None):
        return notifications.notify_guardian(MessageEvent.ATTENDANCE_ABSENT, student or self.child, {})

    def copies(self):
        return Message.objects.filter(user=self.parent_user, channel=MessageChannel.IN_APP)

    def test_an_absence_alert_arrives_in_the_app_addressed_to_the_parent(self):
        self.absent()

        [copy] = self.copies()
        self.assertEqual((self.child.id, "attendance"), (copy.student_id, copy.category))

        response = self.parent.get(f"{FAMILY}/notices")
        self.assertEqual(200, response.status_code, response.data)
        [notice] = response.data["data"]
        self.assertEqual((copy.id, False), (notice["id"], notice["read"]))
        self.assertEqual(1, response.data["unread_count"])
        self.assertNotIn("recipient_mobile", notice)

    def test_the_parents_switch_stops_that_kind(self):
        response = self.parent.patch(f"{FAMILY}/notification-settings", {"attendance": False}, format="json")
        self.assertEqual(200, response.status_code, response.data)
        self.assertFalse(response.data["attendance"])

        self.absent()

        self.assertFalse(self.copies().exists())

    def test_an_emergency_always_arrives(self):
        FamilyNotificationSetting.objects.create(user=self.parent_user, notices=False, attendance=False,
                                                 created_at=timezone.now(), updated_at=timezone.now())

        notifications.notify_guardian(MessageEvent.EMERGENCY_ALERT, self.child, {"subject": "Closing early", "body": "School closes at noon."})

        self.assertTrue(self.copies().exists())

    def test_a_whole_school_notice_arrives_once_for_two_children(self):
        sister = self.student("Meera", MOBILE)
        announcement = Announcement.objects.create(
            school=self.school, title="Sports day", body="Friday on the big field.", audience_type="all_school",
            audience_id=None, audience_label="All School", channels="in_app,sms", published_at=timezone.now(),
            recipients_count=2, sms_count=2, in_app_count=0,
        )

        for child in (self.child, sister):
            notifications.notify_guardian(MessageEvent.ANNOUNCEMENT_PUBLISHED, child, {}, announcement=announcement)

        self.assertEqual(1, self.copies().count())

    def test_the_module_off_sends_no_copy(self):
        ModuleSetting.objects.filter(school=self.school, module="family_app").update(school_enabled=False)

        self.absent()

        self.assertFalse(self.copies().exists())

    def test_another_familys_message_is_not_theirs(self):
        stranger_parent = self.other_family_child()
        self.absent(stranger_parent)

        self.assertFalse(self.copies().exists())
        self.assertEqual([], self.parent.get(f"{FAMILY}/notices").data["data"])

    def test_reading_marks_only_their_own(self):
        self.absent()
        [copy] = self.copies()
        someone_elses = factories.MessageFactory(school=self.school, user=self.admin, channel=MessageChannel.IN_APP)

        self.assertEqual(200, self.parent.post(f"{FAMILY}/notices/{copy.id}/read").status_code)
        self.assertEqual(404, self.parent.post(f"{FAMILY}/notices/{someone_elses.id}/read").status_code)

        self.assertEqual(0, self.parent.get(f"{FAMILY}/notices").data["unread_count"])

    def test_read_all(self):
        self.absent()
        self.absent()

        response = self.parent.post(f"{FAMILY}/notices/read-all")

        self.assertEqual(2, response.data["marked"])

    def test_a_setting_that_is_not_true_or_false_is_refused(self):
        response = self.parent.patch(f"{FAMILY}/notification-settings", {"fee": "maybe"}, format="json")

        self.assertEqual(422, response.status_code)


class AParentRegistersTheirPhoneForPush(FamilyAppTest):
    def test_the_family_app_registers_through_its_own_door(self):
        response = self.parent.post(f"{FAMILY}/devices", {"token": "fcm-1", "platform": "android", "app": "family"},
                                    format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("family", DeviceToken.objects.get(token="fcm-1").app)

    def test_the_staff_door_stays_shut_to_a_family_account(self):
        response = self.parent.post("/api/v1/devices", {"token": "fcm-2", "platform": "android", "app": "family"},
                                    format="json")

        self.assertEqual(403, response.status_code)

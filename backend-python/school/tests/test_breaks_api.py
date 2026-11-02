"""Breaks in the school day - lunch, short breaks (school/school_breaks.py).

A school rings as many as it likes. A break sits between periods and is
never one, and setting one up is meant to be easy: what it clashes with is
named, and a packed day can make room by moving the later periods back.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import AuditLog, Period, SchoolBreak

BREAKS = "/api/v1/breaks"


class BreaksTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

        # Back to back, the way many schools ring them.
        self.p1 = self.period(1, "08:00", "08:45")
        self.p2 = self.period(2, "08:45", "09:30")
        self.p3 = self.period(3, "09:30", "10:15")
        self.p4 = self.period(4, "10:15", "11:00")
        self.p5 = self.period(5, "11:00", "11:45")

    def period(self, number, start, end, shape="full", school=None):
        return factories.PeriodFactory(
            school=school or self.school, period_number=number, day_shape=shape,
            start_time=dt.time.fromisoformat(start), end_time=dt.time.fromisoformat(end),
        )

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def add(self, client=None, **body):
        payload = {"name": "Lunch break", "start_time": "11:45", "end_time": "12:25"}
        payload.update(body)

        return (client or self.client).post(BREAKS, payload, format="json")

    def errors(self, response) -> dict:
        self.assertEqual(422, response.status_code, response.data)

        return response.data["details"]["errors"]

    def times(self, period: Period) -> tuple[str, str]:
        period.refresh_from_db()

        return period.start_time.strftime("%H:%M"), period.end_time.strftime("%H:%M")


class AddingABreak(BreaksTest):
    def test_a_break_in_a_free_gap_is_added(self):
        response = self.add()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(
            {"name": "Lunch break", "day_shape": "full", "start_time": "11:45", "end_time": "12:25"},
            {key: response.data[key] for key in ("name", "day_shape", "start_time", "end_time")},
        )

    def test_several_breaks_a_day(self):
        self.add(name="Lunch break", start_time="11:45", end_time="12:25")
        response = self.add(name="Short break", start_time="12:25", end_time="12:35")

        self.assertEqual(201, response.status_code, response.data)
        listed = self.client.get(BREAKS).data
        self.assertEqual(["Lunch break", "Short break"], [row["name"] for row in listed])

    def test_a_half_day_has_breaks_of_its_own(self):
        response = self.add(name="Short break", day_shape="half", start_time="08:45", end_time="09:00")

        # The full day's Period 2 runs then; a half day rings other bells.
        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("half", response.data["day_shape"])

    def test_it_is_audited(self):
        created = self.add().data

        self.assertTrue(AuditLog.objects.filter(entity_type="school_break", entity_id=created["id"]).exists())


class WhatABreakClashesWith(BreaksTest):
    def test_starting_in_the_middle_of_a_period_says_which_and_when_it_ends(self):
        errors = self.errors(self.add(start_time="10:30", end_time="11:00"))

        self.assertEqual(
            ["It starts during Period 4 (10:15-11:00). Start it when that ends, at 11:00."], errors["start_time"]
        )

    def test_overlapping_the_next_period_offers_to_make_room(self):
        errors = self.errors(self.add(start_time="10:15", end_time="10:45"))

        self.assertIn("It overlaps Period 4 (10:15-11:00).", errors["start_time"][0])
        self.assertIn("Move later periods", errors["start_time"][0])
        self.assertFalse(SchoolBreak.objects.exists())

    def test_overlapping_another_break_is_named(self):
        self.add(name="Lunch break", start_time="11:45", end_time="12:25")

        errors = self.errors(self.add(name="Games", start_time="12:00", end_time="12:30"))

        self.assertIn("the Lunch break (11:45-12:25)", errors["start_time"][0])

    def test_end_before_start_is_refused(self):
        self.assertIn("end_time", self.errors(self.add(start_time="12:30", end_time="12:00")))

    def test_a_blank_name_is_refused(self):
        self.assertIn("name", self.errors(self.add(name="   ")))

    def test_an_unknown_day_shape_is_refused(self):
        self.assertIn("day_shape", self.errors(self.add(day_shape="weekend")))


class MakingRoom(BreaksTest):
    def test_the_later_periods_move_back_by_the_length_of_the_break(self):
        response = self.add(name="Lunch break", start_time="10:15", end_time="10:45", make_room=True)

        self.assertEqual(201, response.status_code, response.data)
        # Before the break: untouched.
        self.assertEqual(("09:30", "10:15"), self.times(self.p3))
        # From the break on: thirty minutes later.
        self.assertEqual(("10:45", "11:30"), self.times(self.p4))
        self.assertEqual(("11:30", "12:15"), self.times(self.p5))

    def test_later_breaks_move_with_them(self):
        short = self.add(name="Short break", start_time="11:45", end_time="11:55").data

        self.add(name="Lunch break", start_time="10:15", end_time="10:45", make_room=True)

        moved = SchoolBreak.objects.get(pk=short["id"])
        self.assertEqual(("12:15", "12:25"), (moved.start_time.strftime("%H:%M"), moved.end_time.strftime("%H:%M")))

    def test_only_that_shape_of_day_moves(self):
        half = self.period(1, "10:15", "11:00", shape="half")

        self.add(start_time="10:15", end_time="10:45", make_room=True)

        self.assertEqual(("10:15", "11:00"), self.times(half))

    def test_making_room_never_fixes_a_break_that_starts_mid_period(self):
        errors = self.errors(self.add(start_time="10:30", end_time="11:00", make_room=True))

        self.assertIn("starts during Period 4", errors["start_time"][0])
        self.assertEqual(("10:15", "11:00"), self.times(self.p4))

    def test_a_day_that_would_run_past_midnight_is_refused_and_nothing_moves(self):
        late = self.period(6, "23:00", "23:50")

        errors = self.errors(self.add(start_time="10:15", end_time="11:15", make_room=True))

        self.assertIn("past midnight", errors["start_time"][0])
        self.assertEqual(("23:00", "23:50"), self.times(late))

    def test_each_moved_period_is_audited(self):
        self.add(start_time="10:15", end_time="10:45", make_room=True)

        self.assertTrue(AuditLog.objects.filter(entity_type="period", entity_id=self.p4.id).exists())


class ChangingABreak(BreaksTest):
    def setUp(self):
        super().setUp()
        self.lunch = self.add().data

    def edit(self, **body):
        return self.client.patch(f"{BREAKS}/{self.lunch['id']}", body, format="json")

    def test_renaming_keeps_the_times(self):
        response = self.edit(name="Lunch")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("Lunch", "11:45", "12:25"), (
            response.data["name"], response.data["start_time"], response.data["end_time"]
        ))

    def test_moving_it_is_checked_against_everything_but_itself(self):
        response = self.edit(start_time="11:50", end_time="12:30")

        self.assertEqual(200, response.status_code, response.data)

    def test_moving_it_into_a_period_is_refused(self):
        self.assertIn("start_time", self.errors(self.edit(start_time="11:00", end_time="11:30")))

    def test_removing_it(self):
        response = self.client.delete(f"{BREAKS}/{self.lunch['id']}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(SchoolBreak.objects.exists())


class PeriodsKeepClearOfBreaks(BreaksTest):
    def test_a_period_may_not_be_set_over_a_break(self):
        self.add(start_time="11:45", end_time="12:25")

        response = self.client.post(
            "/api/v1/periods", {"period_number": 6, "start_time": "12:00", "end_time": "12:45"}, format="json"
        )

        self.assertEqual(422, response.status_code)
        self.assertIn("the Lunch break (11:45-12:25)", response.data["details"]["errors"]["start_time"][0])

    def test_a_period_right_after_a_break_is_fine(self):
        self.add(start_time="11:45", end_time="12:25")

        response = self.client.post(
            "/api/v1/periods", {"period_number": 6, "start_time": "12:25", "end_time": "13:10"}, format="json"
        )

        self.assertEqual(201, response.status_code, response.data)


class WhoMay(BreaksTest):
    def test_a_teacher_reads_the_breaks_but_cannot_change_them(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))
        created = self.add().data

        self.assertEqual(200, teacher.get(BREAKS).status_code)
        self.assertEqual(403, self.add(client=teacher, name="Games", start_time="12:25", end_time="12:40").status_code)
        self.assertEqual(403, teacher.delete(f"{BREAKS}/{created['id']}").status_code)

    def test_another_schools_breaks_are_neither_listed_nor_changeable(self):
        other_school = factories.SchoolFactory()
        other_admin = self.as_user(factories.UserFactory(school=other_school, role=UserRole.SCHOOL_ADMIN))
        created = self.add().data

        self.assertEqual([], other_admin.get(BREAKS).data)
        self.assertEqual(403, other_admin.patch(f"{BREAKS}/{created['id']}", {"name": "Mine"}, format="json").status_code)
        self.assertEqual(403, other_admin.delete(f"{BREAKS}/{created['id']}").status_code)

    def test_a_school_id_in_the_request_does_not_reach_another_school(self):
        other_school = factories.SchoolFactory()

        response = self.add(school_id=other_school.id)

        # The school comes from who is asking, never from the request.
        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])
        self.assertFalse(SchoolBreak.objects.filter(school_id=other_school.id).exists())

    def test_signed_out_is_401(self):
        self.assertEqual(401, APIClient().get(BREAKS).status_code)


class TheTimetableCarriesBellTimes(BreaksTest):
    def test_each_entry_says_when_its_period_runs(self):
        year = factories.AcademicYearFactory(school=self.school)
        section = factories.ClassSectionFactory(school_class=factories.SchoolClassFactory(academic_year=year))
        subject = factories.SubjectFactory(department=factories.DepartmentFactory(school=self.school))
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        factories.TimetableEntryFactory(
            class_section=section, period=self.p4, subject=subject, teacher=teacher, day_of_week="monday"
        )

        row = self.client.get("/api/v1/timetable", {"class_section_id": section.id}).data[0]

        self.assertEqual(("10:15", "11:00"), (row["period_start_time"], row["period_end_time"]))

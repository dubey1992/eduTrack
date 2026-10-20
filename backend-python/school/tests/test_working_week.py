"""The days a school actually runs (docs/holidays.md).

The product is multi-nation - each school already carried its own currency
and its own timezone - but the week was Monday to Friday everywhere, in one
line of application code. A school in the Gulf running Sunday to Thursday had
attendance refused on its own working days, allowed on its days off, and
every rate in every report computed against a week it does not keep.

Stored Monday first, which is `date.weekday()` order. A Sunday-to-Thursday
week is therefore `1111001`, which looks odd written down and is the only
ordering where the index is the weekday and there is no arithmetic to get
wrong.

**The week is the shape of the week, and nothing else.** Holidays stay a
separate question and a separate table; a school closed for Diwali is not a
school that does not run on Tuesdays.
"""

import datetime as dt

from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens, week
from school.enums import UserRole
from school.models import Holiday, Period
from school.services import HolidayService
from school.week import WorkingWeek

SCHOOLS = "/api/v1/schools"

# A week in October 2026: Monday the 19th through Sunday the 25th.
MONDAY = dt.date(2026, 10, 19)
WEEK = [MONDAY + dt.timedelta(days=offset) for offset in range(7)]

GULF = "1111001"      # Sunday to Thursday
SIX_DAY = "1111110"   # Monday to Saturday
HALF_SATURDAY = "1111120"  # the same six days, Saturday a half day
MON_FRI = week.DEFAULT


class TheStoredWeek(TestCase):
    """Reading the column. No database, because this is a string."""

    def test_monday_first_is_the_weekday_index(self):
        self.assertTrue(WorkingWeek("1000000").runs_on(MONDAY))
        self.assertTrue(WorkingWeek("0000001").runs_on(MONDAY + dt.timedelta(days=6)))

    def test_a_sunday_to_thursday_week(self):
        gulf = WorkingWeek(GULF)
        ran = [day.strftime("%a") for day in WEEK if gulf.runs_on(day)]

        self.assertEqual(["Mon", "Tue", "Wed", "Thu", "Sun"], ran)
        self.assertEqual(5, len(gulf))

    def test_a_six_day_week(self):
        six = WorkingWeek(SIX_DAY)

        self.assertEqual(6, len(six))
        self.assertTrue(six.runs_on(MONDAY + dt.timedelta(days=5)))
        self.assertFalse(six.runs_on(MONDAY + dt.timedelta(days=6)))

    def test_the_names_come_back_in_week_order(self):
        self.assertEqual(
            ["monday", "tuesday", "wednesday", "thursday", "sunday"],
            WorkingWeek(GULF).names,
        )

    def test_it_round_trips(self):
        for stored in (MON_FRI, GULF, SIX_DAY, "1111111", "1000000"):
            self.assertEqual(stored, WorkingWeek(stored).stored, stored)


class AWeekItCannotRead(TestCase):
    """**Anything unreadable is the default week.**

    This is asked on every attendance mark and every report row. A column
    somebody edited by hand into nonsense should degrade to the week the
    product assumed for its first year, not take the school offline - a
    school that runs no days refuses every mark on every date with a message
    about being closed, which reads exactly like the product being broken.
    """

    def test_nothing_is_the_default_week(self):
        for bad in (None, "", "garbage", "11111", "11111111", "1111103", 7):
            self.assertEqual(MON_FRI, WorkingWeek(bad).stored, repr(bad))

    def test_a_week_with_no_days_in_it_is_the_default_week(self):
        self.assertEqual(MON_FRI, WorkingWeek("0000000").stored)

    def test_but_a_client_may_not_send_any_of_those(self):
        for bad in (None, "", "garbage", "11111", "11111111", "1111103", "0000000", 7):
            self.assertFalse(week.is_valid(bad), repr(bad))

        for good in (MON_FRI, GULF, SIX_DAY, "1111111", "0000001", HALF_SATURDAY, "2222200"):
            self.assertTrue(week.is_valid(good), good)


class WorkingDatesFollowTheSchool(TestCase):
    """The one helper every date-driven module in the product asks."""

    def dates(self, school):
        return [day.strftime("%a") for day in HolidayService.working_dates(school.id, WEEK[0], WEEK[-1])]

    def test_the_default_school_is_unchanged(self):
        school = factories.SchoolFactory()

        self.assertEqual(["Mon", "Tue", "Wed", "Thu", "Fri"], self.dates(school))

    def test_a_gulf_school_runs_sunday_to_thursday(self):
        school = factories.SchoolFactory(working_days=GULF)

        self.assertEqual(["Mon", "Tue", "Wed", "Thu", "Sun"], self.dates(school))

    def test_a_six_day_school_counts_saturday(self):
        school = factories.SchoolFactory(working_days=SIX_DAY)

        self.assertEqual(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"], self.dates(school))

    def test_two_schools_with_different_weeks_do_not_interfere(self):
        here = factories.SchoolFactory()
        there = factories.SchoolFactory(working_days=GULF)

        self.assertEqual(["Mon", "Tue", "Wed", "Thu", "Fri"], self.dates(here))
        self.assertEqual(["Mon", "Tue", "Wed", "Thu", "Sun"], self.dates(there))

    def test_a_holiday_still_takes_a_day_out_of_its_own_week(self):
        """The two rules are separate and both apply."""
        school = factories.SchoolFactory(working_days=GULF)
        sunday = WEEK[6]
        Holiday.objects.create(
            school=school, name="Prophet's Birthday", type="public", start_date=sunday, end_date=sunday,
            created_at=dt.datetime.now(dt.timezone.utc), updated_at=dt.datetime.now(dt.timezone.utc),
        )

        self.assertEqual(["Mon", "Tue", "Wed", "Thu"], self.dates(school))

    def test_a_holiday_on_a_day_the_school_never_runs_changes_nothing(self):
        school = factories.SchoolFactory(working_days=GULF)
        friday = WEEK[4]
        Holiday.objects.create(
            school=school, name="A day it was closed anyway", type="public", start_date=friday, end_date=friday,
            created_at=dt.datetime.now(dt.timezone.utc), updated_at=dt.datetime.now(dt.timezone.utc),
        )

        self.assertEqual(["Mon", "Tue", "Wed", "Thu", "Sun"], self.dates(school))

    def test_is_working_day_agrees_with_the_list(self):
        school = factories.SchoolFactory(working_days=GULF)

        self.assertTrue(HolidayService.is_working_day(school.id, WEEK[6]))   # Sunday
        self.assertFalse(HolidayService.is_working_day(school.id, WEEK[4]))  # Friday


class OverTheApi(TestCase):
    def setUp(self):
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

    def client_as(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def body(self, **overrides) -> dict:
        data = {
            "name": "Gulf Academy", "email": "gulf@example.invalid", "phone": "+968 90000000",
            "address": "1 Corniche", "city": "Muscat", "state": "Muscat", "country": "Oman",
            "postal_code": "100", "currency_code": "OMR", "timezone": "Asia/Muscat",
        }
        data.update(overrides)

        return data

    def test_a_school_is_created_with_its_own_week(self):
        response = self.client_as(self.root).post(SCHOOLS, self.body(working_days=GULF), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(GULF, response.data["working_days"])
        self.assertEqual(
            ["monday", "tuesday", "wednesday", "thursday", "sunday"],
            response.data["working_day_names"],
        )

    def test_a_school_created_without_one_keeps_the_week_the_product_assumed(self):
        response = self.client_as(self.root).post(SCHOOLS, self.body(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(MON_FRI, response.data["working_days"])

    def test_the_week_can_be_changed_later(self):
        school = factories.SchoolFactory()

        response = self.client_as(self.root).patch(
            f"{SCHOOLS}/{school.id}",
            self.body(name=school.name, email=school.email, working_days=SIX_DAY),
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        school.refresh_from_db()
        self.assertEqual(SIX_DAY, school.working_days)

    def test_a_week_nobody_could_keep_is_refused(self):
        for bad in ("0000000", "11111", "garbage", "1111103"):
            response = self.client_as(self.root).post(
                SCHOOLS, self.body(email=f"x{bad}@example.invalid", working_days=bad), format="json"
            )

            self.assertEqual(422, response.status_code, bad)
            self.assertIn("working_days", response.data["details"]["errors"], bad)

    def test_changing_it_is_audited(self):
        """It moves every working-day figure the school has, so it is not a
        change anybody should be able to make invisibly."""
        from school.models import AuditLog

        school = factories.SchoolFactory()
        self.client_as(self.root).patch(
            f"{SCHOOLS}/{school.id}",
            self.body(name=school.name, email=school.email, working_days=GULF),
            format="json",
        )

        entry = AuditLog.objects.filter(entity_type="school", entity_id=school.id).latest("id")

        self.assertEqual(MON_FRI, entry.old_values["working_days"])
        self.assertEqual(GULF, entry.new_values["working_days"])


def _last(weekday: int, before: dt.date) -> dt.date:
    """The most recent `weekday` strictly before `before`.

    Derived rather than pinned for the reason test_attendance_api derives
    its own dates: a register may only be taken for the last 30 days, so a
    fixed date passes for a month and then fails for ever.
    """
    return before - dt.timedelta(days=(before.weekday() - weekday) % 7 or 7)


class MarkingAttendanceOnTheSchoolsOwnWeek(TestCase):
    """End to end, because a helper being right is not the claim.

    The claim is that a school in the Gulf can take a register on a Sunday
    and cannot on a Friday - which is the opposite of what this product did
    for its first year.
    """

    def setUp(self):
        today = dt.date.today()
        self.sunday = _last(6, today)
        self.friday = _last(4, today)

        self.school = factories.SchoolFactory(working_days=GULF, timezone="Asia/Muscat")
        year = factories.AcademicYearFactory(
            school=self.school,
            is_current=True,
            start_date=today - dt.timedelta(days=365),
            end_date=today + dt.timedelta(days=365),
        )
        section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(academic_year=year, school=self.school, name="Grade 8"),
            name="A",
        )
        self.section = section
        self.students = [
            factories.StudentFactory(
                school=self.school, class_section=section, admission_number=f"OM-{index}",
                first_name=f"Student{index}", guardian_mobile="+968 90000000",
            )
            for index in range(2)
        ]
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def mark(self, on: dt.date):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))

        return client.post(
            "/api/v1/attendance",
            {
                "class_section_id": self.section.id,
                "attendance_date": on.isoformat(),
                "records": [{"student_id": student.id, "status": "present"} for student in self.students],
            },
            format="json",
        )

    def test_a_register_is_taken_on_sunday(self):
        response = self.mark(self.sunday)

        self.assertEqual(201, response.status_code, response.data)

    def test_no_register_is_taken_on_friday(self):
        response = self.mark(self.friday)

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual("NON_WORKING_DAY", response.data["code"])
        # Not "a weekend": Friday is this school's day off, and for a
        # six-day school the day off is Sunday alone. The message has to be
        # true whatever shape the week is.
        self.assertNotIn("weekend", response.data["message"].lower())

    def test_the_same_dates_the_other_way_round_for_a_monday_to_friday_school(self):
        """The default school is unchanged, which is most of them."""
        self.school.working_days = MON_FRI
        self.school.save()

        self.assertEqual(201, self.mark(self.friday).status_code)
        self.assertEqual(409, self.mark(self.sunday).status_code)


class WhatTheSessionCarries(TestCase):
    """The screens need the week before they can lay anything out.

    A timetable grid that assumed Monday to Friday would offer a teacher in
    the Gulf a column the server refuses to write to.
    """

    def session_for(self, user) -> dict:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client.get("/api/v1/me").data

    def test_a_school_user_gets_their_schools_week(self):
        school = factories.SchoolFactory(working_days=GULF)
        teacher = factories.UserFactory(school=school, role=UserRole.TEACHER)

        self.assertEqual(GULF, self.session_for(teacher)["working_days"])

    def test_a_super_admin_belongs_to_no_school_and_gets_the_default(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertEqual(MON_FRI, self.session_for(root)["working_days"])

    def test_it_follows_the_school_being_changed(self):
        school = factories.SchoolFactory()
        teacher = factories.UserFactory(school=school, role=UserRole.TEACHER)

        self.assertEqual(MON_FRI, self.session_for(teacher)["working_days"])

        school.working_days = SIX_DAY
        school.save()

        self.assertEqual(SIX_DAY, self.session_for(teacher)["working_days"])


class TheTimetableFollowsTheWeekToo(TestCase):
    """A period can only exist on a day the school runs.

    The enum carries all seven days now, because the week belongs to the
    school. Without this check that would let anybody put a Saturday period
    on a Monday-to-Friday school's grid: a cell nobody can ever teach, and a
    teaching report that can never be filed against it.
    """

    def setUp(self):
        self.school = factories.SchoolFactory(working_days=GULF)
        self.year = factories.AcademicYearFactory(school=self.school, is_current=True)
        self.section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=self.school, academic_year=self.year)
        )
        self.period = factories.PeriodFactory(school=self.school)
        self.subject = factories.SubjectFactory(school=self.school)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def put(self, day: str):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))

        return client.post(
            "/api/v1/timetable",
            {
                "class_section_id": self.section.id,
                "period_id": self.period.id,
                "day_of_week": day,
                "subject_id": self.subject.id,
                "teacher_id": self.teacher.id,
            },
            format="json",
        )

    def test_a_period_on_sunday_is_allowed_for_a_school_that_runs_sundays(self):
        self.assertIn(self.put("sunday").status_code, (200, 201))

    def test_a_period_on_friday_is_refused_for_a_school_that_does_not(self):
        response = self.put("friday")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            ["The school does not run on that day."],
            response.data["details"]["errors"]["day_of_week"],
        )

    def test_a_day_that_is_not_a_day_is_still_refused(self):
        self.assertEqual(422, self.put("caturday").status_code)

    def test_the_default_school_still_refuses_saturday(self):
        self.school.working_days = MON_FRI
        self.school.save()

        self.assertEqual(422, self.put("saturday").status_code)
        self.assertIn(self.put("friday").status_code, (200, 201))


class TheShapeOfADay(TestCase):
    """A full day's periods and a half day's (docs/holidays.md, H1).

    **A half day is a full working day.** It is a shorter day, not a fraction
    of one: the school ran, and a teacher who was there all morning worked a
    full Saturday. What the shape decides is which periods the day has, and
    nothing that counts working days cares.
    """

    def test_a_half_day_counts_as_a_day(self):
        school = factories.SchoolFactory(working_days=HALF_SATURDAY)

        self.assertEqual(6, len(HolidayService.week_of(school.id)))
        self.assertEqual(
            ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat"],
            [day.strftime("%a") for day in HolidayService.working_dates(school.id, WEEK[0], WEEK[-1])],
        )

    def test_the_shape_is_readable_per_day(self):
        week_of = WorkingWeek(HALF_SATURDAY)

        self.assertEqual("full", week_of.shape_on(WEEK[0]))     # Monday
        self.assertEqual("half", week_of.shape_on(WEEK[5]))     # Saturday
        self.assertIsNone(week_of.shape_on(WEEK[6]))            # Sunday, closed
        self.assertEqual("half", week_of.shape_of("saturday"))
        self.assertIsNone(week_of.shape_of("sunday"))

    def test_a_day_nobody_marked_half_is_a_full_day(self):
        self.assertEqual({name: "full" for name in WorkingWeek(MON_FRI).names}, WorkingWeek(MON_FRI).shapes)


class PeriodsBelongToAShape(TestCase):
    def setUp(self):
        self.school = factories.SchoolFactory(working_days=HALF_SATURDAY)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def client_as(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def create(self, **overrides):
        body = {"period_number": 1, "start_time": "09:00", "end_time": "09:55"}
        body.update(overrides)

        return self.client_as(self.admin).post("/api/v1/periods", body, format="json")

    def test_a_period_is_a_full_days_unless_somebody_says_otherwise(self):
        response = self.create()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("full", response.data["day_shape"])

    def test_a_half_days_period_can_be_created(self):
        response = self.create(day_shape="half", start_time="09:00", end_time="09:40")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("half", response.data["day_shape"])

    def test_the_same_number_in_each_shape_is_not_a_duplicate(self):
        """A full day's period 1 and a half day's period 1 are different
        bells at different times, and neither is a duplicate of the other."""
        self.assertEqual(201, self.create().status_code)
        self.assertEqual(201, self.create(day_shape="half", end_time="09:40").status_code)

        self.assertEqual(2, Period.objects.filter(school=self.school, period_number=1).count())

    def test_the_same_number_in_the_same_shape_still_is(self):
        self.assertEqual(201, self.create().status_code)

        response = self.create(start_time="10:00", end_time="10:55")

        self.assertEqual(422, response.status_code)
        self.assertIn("period_number", response.data["details"]["errors"])

    def test_a_shape_that_is_not_one_is_refused(self):
        response = self.create(day_shape="quarter")

        self.assertEqual(422, response.status_code)
        self.assertIn("day_shape", response.data["details"]["errors"])

    def test_renumbering_a_half_days_period_is_checked_against_half_days(self):
        self.create(period_number=2)
        half = self.create(day_shape="half", period_number=1, end_time="09:40").data

        # Period 2 is taken on the full day, and free on the half day.
        response = self.client_as(self.admin).patch(
            f"/api/v1/periods/{half['id']}", {"period_number": 2}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(("half", 2), (response.data["day_shape"], response.data["period_number"]))


class ThePeriodMustSuitTheDay(TestCase):
    """A full day's bells do not ring on a half day.

    Without this, a cell on Saturday could point at period 7 of a full day -
    an hour that does not exist on a day ending at noon, and a teaching
    report that can never be filed against it.
    """

    def setUp(self):
        self.school = factories.SchoolFactory(working_days=HALF_SATURDAY)
        self.year = factories.AcademicYearFactory(school=self.school, is_current=True)
        self.section = factories.ClassSectionFactory(
            school_class=factories.SchoolClassFactory(school=self.school, academic_year=self.year)
        )
        self.full = factories.PeriodFactory(school=self.school, period_number=1, day_shape="full")
        self.half = factories.PeriodFactory(
            school=self.school, period_number=1, day_shape="half",
            start_time=dt.time(9, 0), end_time=dt.time(9, 40),
        )
        self.subject = factories.SubjectFactory(school=self.school)
        self.teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

    def put(self, period, day: str):
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(self.admin))

        return client.post(
            "/api/v1/timetable",
            {
                "class_section_id": self.section.id,
                "period_id": period.id,
                "day_of_week": day,
                "subject_id": self.subject.id,
                "teacher_id": self.teacher.id,
            },
            format="json",
        )

    def test_a_full_days_period_on_a_full_day(self):
        self.assertIn(self.put(self.full, "monday").status_code, (200, 201))

    def test_a_half_days_period_on_the_half_day(self):
        self.assertIn(self.put(self.half, "saturday").status_code, (200, 201))

    def test_a_full_days_period_on_the_half_day_is_refused(self):
        response = self.put(self.full, "saturday")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            ["That period is not one this day runs."],
            response.data["details"]["errors"]["period_id"],
        )

    def test_a_half_days_period_on_a_full_day_is_refused(self):
        response = self.put(self.half, "monday")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("period_id", response.data["details"]["errors"])

    def test_a_day_the_school_does_not_run_is_still_refused_first(self):
        """The day is the earlier question: there is no shape to check."""
        response = self.put(self.full, "sunday")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["The school does not run on that day."],
            response.data["details"]["errors"]["day_of_week"],
        )

    def test_a_school_with_no_half_days_is_untouched(self):
        """The test that this cost nobody anything."""
        self.school.working_days = MON_FRI
        self.school.save()

        self.assertIn(self.put(self.full, "monday").status_code, (200, 201))

"""Charging students (docs/fees.md, F2 "Dues"): the one reconcile,
FeeDueService.sync_student, and every write that calls it - publishing a fee,
editing a published one, admitting, moving and deactivating a student, bus
routes, promotion - plus the repair command. The two read endpoints are
test_fees_dues_api.py.

The school is in Asia/Kolkata. The academic year is 2026-27 (1 April 2026 to
31 March 2027), and "now" is frozen at 15 July 2026, 11:30 in Kolkata - so
the April and July installments are already due and October and January are
still to come.
"""

import datetime as dt
import io
from decimal import Decimal
from unittest import mock

from django.core.cache import cache
from django.core.management import call_command
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import EnrollmentStatus, FeeDueStatus, StudentStatus, UserRole
from school.fees.dues import FeeDueService
from school.models import (
    AuditLog,
    FeeHead,
    FeeInstallment,
    FeeStructure,
    Student,
    StudentEnrollment,
    StudentFeeDue,
    StudentTransportAssignment,
)

NOW = dt.datetime(2026, 7, 15, 6, 0, tzinfo=dt.timezone.utc)

STRUCTURES = "/api/v1/fees/structures"
STUDENTS = "/api/v1/students"

# Class 8's Tuition: 4,000 a year in four installments.
TUITION_8 = [
    ("April", dt.date(2026, 4, 10), "1000.00"),
    ("July", dt.date(2026, 7, 10), "1000.00"),
    ("October", dt.date(2026, 10, 10), "1000.00"),
    ("January", dt.date(2027, 1, 10), "1000.00"),
]
# Class 9's: 3,000 in two, both still to come.
TUITION_9 = [
    ("Term 2", dt.date(2026, 10, 10), "1500.00"),
    ("Term 3", dt.date(2027, 1, 10), "1500.00"),
]
ROUTE_A = [("Bus 1", dt.date(2026, 4, 10), "600.00"), ("Bus 2", dt.date(2026, 10, 10), "600.00")]
ROUTE_B = [("Bus B", dt.date(2026, 10, 10), "800.00")]


class DuesTestCase(TestCase):
    def setUp(self):
        cache.clear()
        clock = mock.patch("django.utils.timezone.now", return_value=NOW)
        clock.start()
        self.addCleanup(clock.stop)

        self.school = factories.SchoolFactory(name="Sunrise Public School", currency_code="INR",
                                              timezone="Asia/Kolkata")
        factories.ModuleSettingFactory(school=self.school, module="fees")
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31),
            is_current=True,
        )
        self.class8 = factories.SchoolClassFactory(academic_year=self.year, name="Class 8", level=8)
        self.section8 = factories.ClassSectionFactory(school_class=self.class8, name="A")
        self.class9 = factories.SchoolClassFactory(academic_year=self.year, name="Class 9", level=9)
        self.section9 = factories.ClassSectionFactory(school_class=self.class9, name="A")

        self.route_a = factories.TransportRouteFactory(school=self.school, name="Route A")
        self.stop_a = factories.TransportStopFactory(route=self.route_a)
        self.route_b = factories.TransportRouteFactory(school=self.school, name="Route B")
        self.stop_b = factories.TransportStopFactory(route=self.route_b)

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)

        self.tuition = FeeHead.objects.create(school=self.school, name="Tuition")
        self.transport = FeeHead.objects.create(school=self.school, name="Transport", is_transport=True)

    # -- helpers ------------------------------------------------------------

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def student(self, first_name="Aarav", section=None, admission=dt.date(2026, 4, 1), enrolled=True, year=None,
                **fields) -> Student:
        section = section or self.section8
        student = factories.StudentFactory(
            school=self.school, class_section=section, first_name=first_name, admission_date=admission, **fields
        )

        if enrolled:
            # The roll number copied, as StudentEnrollmentService does.
            factories.StudentEnrollmentFactory(
                student=student, school=self.school, academic_year=year or self.year,
                school_class=section.school_class, class_section=section, roll_number=student.roll_number,
            )

        return student

    def fee(self, rows, school_class=None, route=None, head=None, year=None, status="draft") -> FeeStructure:
        """A fee written straight to the table, as F1 left it: a draft
        unless asked, nobody charged."""
        year = year or self.year
        total = sum((Decimal(amount) for _, _, amount in rows), Decimal("0.00"))
        structure = FeeStructure.objects.create(
            school=self.school, academic_year=year, school_class=school_class, transport_route=route,
            fee_head=head or (self.transport if route is not None else self.tuition), amount=total,
            currency_code="INR", frequency="term", status=status,
        )

        for sequence, (label, due, amount) in enumerate(rows, start=1):
            FeeInstallment.objects.create(
                fee_structure=structure, sequence=sequence, label=label, due_date=due, amount=amount,
            )

        return structure

    def publish(self, structure):
        response = self.as_user(self.accountant).post(f"{STRUCTURES}/{structure.id}/publish")
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    def published(self, rows, **kwargs) -> FeeStructure:
        structure = self.fee(rows, **kwargs)
        self.publish(structure)

        return structure

    def ledger(self, student) -> list[tuple]:
        """(label, due date, amount, status, reason) for each of a student's
        dues, oldest first."""
        return [
            (due.label, due.due_date.isoformat(), str(due.amount), due.status, due.cancelled_reason)
            for due in StudentFeeDue.objects.filter(student_id=student.id).order_by("due_date", "label", "id")
        ]

    def owing(self, student) -> list[str]:
        """The labels of the dues a student still owes."""
        return [label for label, _, _, status, _ in self.ledger(student) if status != FeeDueStatus.CANCELLED]

    def patch_student(self, student, body):
        response = self.as_user(self.admin).patch(f"{STUDENTS}/{student.id}", body, format="json")
        self.assertEqual(200, response.status_code, response.data)

        return response.data

    def ride(self, student, route, stop):
        response = self.as_user(self.admin).put(
            f"{STUDENTS}/{student.id}/transport", {"route_id": route.id, "transport_stop_id": stop.id}, format="json"
        )
        self.assertEqual(200, response.status_code, response.data)


# -- publishing ---------------------------------------------------------------


class PublishingCharges(DuesTestCase):
    def test_publishing_charges_every_active_student_enrolled_in_the_class_and_nobody_else(self):
        aarav = self.student("Aarav")
        bina = self.student("Bina")
        gone = self.student("Chetan", status=StudentStatus.INACTIVE)
        unenrolled = self.student("Divya", enrolled=False)
        elsewhere = self.student("Esha", section=self.section9)
        structure = self.fee(TUITION_8, school_class=self.class8)

        data = self.publish(structure)

        self.assertEqual("published", data["status"])
        self.assertEqual({"students": 2, "dues_created": 8}, data["charged"])
        self.assertEqual(2, data["students_count"])
        self.assertEqual(
            [
                ("Tuition - April", "2026-04-10", "1000.00", "pending", None),
                ("Tuition - July", "2026-07-10", "1000.00", "pending", None),
                ("Tuition - October", "2026-10-10", "1000.00", "pending", None),
                ("Tuition - January", "2027-01-10", "1000.00", "pending", None),
            ],
            self.ledger(aarav),
        )
        self.assertEqual(4, len(self.ledger(bina)))

        for nobody in (gone, unenrolled, elsewhere):
            self.assertEqual([], self.ledger(nobody), nobody.first_name)

        due = StudentFeeDue.objects.filter(student=aarav).first()
        self.assertEqual(
            (self.school.id, self.year.id, structure.id, self.tuition.id, "INR", Decimal("0"), Decimal("0")),
            (due.school_id, due.academic_year_id, due.fee_structure_id, due.fee_head_id, due.currency_code,
             due.discount_amount, due.paid_amount),
        )

        entry = AuditLog.objects.get(action="fee_dues.synced")
        self.assertEqual(
            ("fees", "fee_structure", structure.id, self.school.id, self.accountant.id),
            (entry.module, entry.entity_type, entry.entity_id, entry.school_id, entry.user_id),
        )
        self.assertEqual({"created": 8, "revived": 0, "cancelled": 0, "updated": 0}, entry.new_values)

    def test_publishing_twice_charges_once_and_says_nothing_the_second_time(self):
        aarav = self.student()
        structure = self.fee(TUITION_8, school_class=self.class8)

        self.publish(structure)
        again = self.publish(structure)

        self.assertEqual({"students": 0, "dues_created": 0}, again["charged"])
        self.assertEqual(4, StudentFeeDue.objects.filter(student=aarav).count())
        self.assertEqual(1, AuditLog.objects.filter(action="fee_dues.synced").count())

    def test_a_route_fee_charges_the_enrolled_students_riding_the_route(self):
        rider = self.student("Aarav")
        StudentTransportAssignment.objects.create(
            school=self.school, student=rider, route=self.route_a, transport_stop=self.stop_a
        )
        walker = self.student("Bina")
        not_this_year = self.student("Chetan", enrolled=False)
        StudentTransportAssignment.objects.create(
            school=self.school, student=not_this_year, route=self.route_a, transport_stop=self.stop_a
        )

        data = self.publish(self.fee(ROUTE_A, route=self.route_a))

        self.assertEqual({"students": 1, "dues_created": 2}, data["charged"])
        self.assertEqual(["Transport - Bus 1", "Transport - Bus 2"], self.owing(rider))
        self.assertEqual([], self.ledger(walker))
        self.assertEqual([], self.ledger(not_this_year))

    def test_publishing_a_year_charges_each_student_once_for_every_fee(self):
        aarav = self.student("Aarav")
        StudentTransportAssignment.objects.create(
            school=self.school, student=aarav, route=self.route_a, transport_stop=self.stop_a
        )
        bina = self.student("Bina", section=self.section9)
        self.fee(TUITION_8, school_class=self.class8)
        self.fee(TUITION_9, school_class=self.class9)
        self.fee(ROUTE_A, route=self.route_a)

        response = self.as_user(self.accountant).post(
            f"{STRUCTURES}/publish", {"academic_year_id": self.year.id}, format="json"
        )

        self.assertEqual({"published": 3, "students": 2, "dues_created": 8}, response.data)
        self.assertEqual(6, len(self.owing(aarav)))
        self.assertEqual(2, len(self.owing(bina)))
        entry = AuditLog.objects.get(action="fee_dues.synced")
        self.assertEqual(("academic_year", self.year.id), (entry.entity_type, entry.entity_id))

    def test_a_draft_charges_nobody(self):
        aarav = self.student()
        self.fee(TUITION_8, school_class=self.class8)

        FeeDueService.sync_student(aarav, self.year)

        self.assertEqual([], self.ledger(aarav))


# -- who joined when ----------------------------------------------------------


class JoiningLate(DuesTestCase):
    def test_a_mid_year_joiner_is_charged_only_what_falls_due_from_their_admission(self):
        late = self.student("Aarav", admission=dt.date(2026, 8, 1))
        on_the_day = self.student("Bina", admission=dt.date(2026, 7, 10))

        self.published(TUITION_8, school_class=self.class8)

        self.assertEqual(["Tuition - October", "Tuition - January"], self.owing(late))
        self.assertEqual(["Tuition - July", "Tuition - October", "Tuition - January"], self.owing(on_the_day))

    def test_without_an_admission_date_the_school_local_day_the_record_was_made_counts(self):
        # 20:00 UTC on 10 October is 01:30 on the 11th in Kolkata: the
        # October installment, due on the 10th, came before they joined. The
        # UTC date would have charged it.
        late = self.student("Aarav", admission=None)
        Student.objects.filter(pk=late.id).update(created_at=dt.datetime(2026, 10, 10, 20, 0, tzinfo=dt.timezone.utc))
        same_day = self.student("Bina", admission=None)
        Student.objects.filter(pk=same_day.id).update(
            created_at=dt.datetime(2026, 10, 10, 10, 0, tzinfo=dt.timezone.utc)
        )

        self.published(TUITION_8, school_class=self.class8)

        self.assertEqual(["Tuition - January"], self.owing(late))
        self.assertEqual(["Tuition - October", "Tuition - January"], self.owing(same_day))

    def test_giving_an_earlier_admission_date_charges_what_it_now_covers(self):
        late = self.student("Aarav", admission=dt.date(2026, 8, 1))
        self.published(TUITION_8, school_class=self.class8)

        data = self.patch_student(late, {"admission_date": "2026-04-01"})

        self.assertEqual("2026-04-01", data["admission_date"])
        self.assertEqual(4, len(self.owing(late)))
        entry = AuditLog.objects.get(action="fee_dues.synced", entity_type="student")
        self.assertEqual((late.id, {"created": 2, "revived": 0, "cancelled": 0, "updated": 0}),
                         (entry.entity_id, entry.new_values))

    def test_a_later_admission_date_cancels_only_what_has_not_fallen_due(self):
        aarav = self.student("Aarav")
        self.published(TUITION_8, school_class=self.class8)

        self.patch_student(aarav, {"admission_date": "2026-11-01"})

        self.assertEqual(
            [
                ("Tuition - April", "2026-04-10", "1000.00", "pending", None),
                ("Tuition - July", "2026-07-10", "1000.00", "pending", None),
                ("Tuition - October", "2026-10-10", "1000.00", "cancelled", "fee_changed"),
                ("Tuition - January", "2027-01-10", "1000.00", "pending", None),
            ],
            self.ledger(aarav),
        )

    def test_a_student_admitted_through_the_api_is_charged_at_once(self):
        self.published(TUITION_8, school_class=self.class8)

        response = self.as_user(self.admin).post(STUDENTS, {
            "class_section_id": self.section8.id, "admission_number": "ADM-77", "first_name": "Farah",
            "last_name": "Khan", "guardian_name": "Zoya Khan", "admission_date": "2026-09-01",
        }, format="json")

        self.assertEqual(201, response.status_code, response.data)
        farah = Student.objects.get(pk=response.data["id"])
        self.assertEqual(["Tuition - October", "Tuition - January"], self.owing(farah))
        self.assertTrue(AuditLog.objects.filter(action="fee_dues.synced", entity_type="student",
                                                entity_id=farah.id).exists())

    def test_admitted_without_a_date_counts_from_today(self):
        self.published(TUITION_8, school_class=self.class8)

        response = self.as_user(self.admin).post(STUDENTS, {
            "class_section_id": self.section8.id, "admission_number": "ADM-78", "first_name": "Gita",
            "last_name": "Rao", "guardian_name": "Ravi Rao",
        }, format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertIsNone(response.data["admission_date"])
        self.assertEqual(["Tuition - October", "Tuition - January"],
                         self.owing(Student.objects.get(pk=response.data["id"])))


# -- leaving ------------------------------------------------------------------


class Leaving(DuesTestCase):
    def test_deactivating_cancels_what_falls_due_after_today_and_the_overdue_stays_owed(self):
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)
        ids = list(StudentFeeDue.objects.filter(student=aarav).order_by("due_date").values_list("id", flat=True))

        self.assertEqual(200, self.as_user(self.admin).patch(f"{STUDENTS}/{aarav.id}/deactivate").status_code)

        self.assertEqual(
            [
                ("Tuition - April", "2026-04-10", "1000.00", "pending", None),
                ("Tuition - July", "2026-07-10", "1000.00", "pending", None),
                ("Tuition - October", "2026-10-10", "1000.00", "cancelled", "left"),
                ("Tuition - January", "2027-01-10", "1000.00", "cancelled", "left"),
            ],
            self.ledger(aarav),
        )
        self.assertIsNotNone(StudentFeeDue.objects.get(pk=ids[2]).cancelled_at)

        # Coming back revives the same rows - the unique key allows one per
        # installment - rather than adding new ones.
        self.assertEqual(200, self.as_user(self.admin).patch(f"{STUDENTS}/{aarav.id}/activate").status_code)

        self.assertEqual(ids, list(StudentFeeDue.objects.filter(student=aarav).order_by("due_date")
                                   .values_list("id", flat=True)))
        self.assertEqual(4, len(self.owing(aarav)))
        revived = StudentFeeDue.objects.get(pk=ids[3])
        self.assertEqual((None, None), (revived.cancelled_reason, revived.cancelled_at))
        self.assertEqual(
            [{"created": 0, "revived": 0, "cancelled": 2, "updated": 0},
             {"created": 0, "revived": 2, "cancelled": 0, "updated": 0}],
            [entry.new_values for entry in AuditLog.objects.filter(action="fee_dues.synced", entity_type="student")
             .order_by("id")],
        )

    def test_a_due_with_money_against_it_is_never_cancelled(self):
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)
        StudentFeeDue.objects.filter(student=aarav, label="Tuition - October").update(
            status=FeeDueStatus.PARTIAL, paid_amount="400.00"
        )
        StudentFeeDue.objects.filter(student=aarav, label="Tuition - January").update(
            status=FeeDueStatus.PAID, paid_amount="1000.00"
        )

        self.as_user(self.admin).patch(f"{STUDENTS}/{aarav.id}/deactivate")

        self.assertEqual(["partial", "paid"], [status for label, _, _, status, _ in self.ledger(aarav)
                                               if label in ("Tuition - October", "Tuition - January")])

    def test_a_due_falling_due_today_in_the_schools_timezone_stays_owed(self):
        # 20:00 UTC on 9 October is already the 10th in Kolkata: the October
        # installment is due today there, so it is not "after today".
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)

        with mock.patch("django.utils.timezone.now",
                        return_value=dt.datetime(2026, 10, 9, 20, 0, tzinfo=dt.timezone.utc)):
            FeeDueService.sync_student(Student.objects.get(pk=aarav.id), self.year)
            Student.objects.filter(pk=aarav.id).update(status=StudentStatus.INACTIVE)
            FeeDueService.sync_student(aarav, self.year)

        self.assertEqual("pending", StudentFeeDue.objects.get(student=aarav, label="Tuition - October").status)
        self.assertEqual("cancelled", StudentFeeDue.objects.get(student=aarav, label="Tuition - January").status)


# -- moving class -------------------------------------------------------------


class MovingClass(DuesTestCase):
    def test_moving_class_cancels_the_old_classes_future_dues_and_charges_the_new_ones(self):
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)
        self.published(TUITION_9, school_class=self.class9)

        self.patch_student(aarav, {"class_section_id": self.section9.id})

        self.assertEqual(
            [
                ("Tuition - April", "2026-04-10", "1000.00", "pending", None),
                ("Tuition - July", "2026-07-10", "1000.00", "pending", None),
                ("Tuition - October", "2026-10-10", "1000.00", "cancelled", "class_changed"),
                ("Tuition - Term 2", "2026-10-10", "1500.00", "pending", None),
                ("Tuition - January", "2027-01-10", "1000.00", "cancelled", "class_changed"),
                ("Tuition - Term 3", "2027-01-10", "1500.00", "pending", None),
            ],
            self.ledger(aarav),
        )
        self.assertEqual(self.class9.id, StudentEnrollment.objects.get(student=aarav, academic_year=self.year)
                         .school_class_id)

    def test_moving_back_revives_the_cancelled_dues_and_cancels_the_others(self):
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)
        self.published(TUITION_9, school_class=self.class9)
        before = set(StudentFeeDue.objects.filter(student=aarav).values_list("id", flat=True))

        self.patch_student(aarav, {"class_section_id": self.section9.id})
        self.patch_student(aarav, {"class_section_id": self.section8.id})

        self.assertEqual(before, set(StudentFeeDue.objects.filter(student=aarav, status="pending")
                                     .values_list("id", flat=True)))
        self.assertEqual(["class_changed", "class_changed"], list(
            StudentFeeDue.objects.filter(student=aarav, fee_structure__school_class=self.class9)
            .values_list("cancelled_reason", flat=True)
        ))

    def test_moving_sections_within_a_class_changes_nothing(self):
        aarav = self.student()
        section_b = factories.ClassSectionFactory(school_class=self.class8, name="B")
        self.published(TUITION_8, school_class=self.class8)

        self.patch_student(aarav, {"class_section_id": section_b.id})

        self.assertEqual(4, len(self.owing(aarav)))
        self.assertFalse(AuditLog.objects.filter(action="fee_dues.synced", entity_type="student").exists())

    def test_editing_other_fields_does_not_reconcile(self):
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)

        with mock.patch.object(FeeDueService, "sync_student_everywhere") as sync:
            self.patch_student(aarav, {"guardian_name": "Somebody Else"})

        sync.assert_not_called()


# -- bus routes ---------------------------------------------------------------


class BusRoutes(DuesTestCase):
    def test_given_a_route_changed_route_and_taken_off_the_bus(self):
        aarav = self.student()
        self.published(ROUTE_A, route=self.route_a)
        self.published(ROUTE_B, route=self.route_b)

        self.ride(aarav, self.route_a, self.stop_a)
        self.assertEqual(["Transport - Bus 1", "Transport - Bus 2"], self.owing(aarav))

        self.ride(aarav, self.route_b, self.stop_b)
        self.assertEqual(
            [
                ("Transport - Bus 1", "2026-04-10", "600.00", "pending", None),
                ("Transport - Bus 2", "2026-10-10", "600.00", "cancelled", "route_changed"),
                ("Transport - Bus B", "2026-10-10", "800.00", "pending", None),
            ],
            self.ledger(aarav),
        )

        self.assertEqual(200, self.as_user(self.admin).delete(f"{STUDENTS}/{aarav.id}/transport").status_code)
        self.assertEqual(["Transport - Bus 1"], self.owing(aarav))
        self.assertEqual("route_changed", StudentFeeDue.objects.get(student=aarav, label="Transport - Bus B")
                         .cancelled_reason)

        # Back on Route A: its October line comes back to life.
        self.ride(aarav, self.route_a, self.stop_a)
        self.assertEqual(["Transport - Bus 1", "Transport - Bus 2"], self.owing(aarav))
        self.assertEqual(3, StudentFeeDue.objects.filter(student=aarav).count())

        entries = AuditLog.objects.filter(action="fee_dues.synced", entity_type="transport_assignment")
        self.assertEqual(4, entries.count())

    def test_moving_between_a_routes_own_stops_changes_nothing(self):
        aarav = self.student()
        self.published(ROUTE_A, route=self.route_a)
        self.ride(aarav, self.route_a, self.stop_a)
        other_stop = factories.TransportStopFactory(route=self.route_a)

        with mock.patch.object(FeeDueService, "sync_route_change") as sync:
            self.ride(aarav, self.route_a, other_stop)

        sync.assert_not_called()

    def test_a_route_without_a_published_fee_charges_nothing(self):
        aarav = self.student()
        self.fee(ROUTE_A, route=self.route_a)

        self.ride(aarav, self.route_a, self.stop_a)

        self.assertEqual([], self.ledger(aarav))
        self.assertFalse(AuditLog.objects.filter(action="fee_dues.synced").exists())


# -- editing a published fee --------------------------------------------------


class EditingAPublishedFee(DuesTestCase):
    def put(self, structure, rows, amount=None):
        total = amount or str(sum(Decimal(row[2]) for row in rows))

        return self.as_user(self.accountant).put(f"{STRUCTURES}/{structure.id}", {
            "amount": total, "frequency": "term",
            "installments": [{"label": label, "due_date": due.isoformat(), "amount": value} for label, due, value in rows],
        }, format="json")

    def test_unpaid_dues_follow_part_paid_never_drop_below_what_was_paid_and_paid_are_untouched(self):
        aarav = self.student()
        structure = self.published(TUITION_8, school_class=self.class8)
        installment_ids = list(FeeInstallment.objects.filter(fee_structure=structure).order_by("sequence")
                               .values_list("id", flat=True))
        StudentFeeDue.objects.filter(student=aarav, label="Tuition - April").update(
            status=FeeDueStatus.PAID, paid_amount="1000.00"
        )
        StudentFeeDue.objects.filter(student=aarav, label="Tuition - July").update(
            status=FeeDueStatus.PARTIAL, paid_amount="700.00"
        )

        response = self.put(structure, [
            ("April", dt.date(2026, 4, 10), "500.00"),
            ("July", dt.date(2026, 7, 10), "500.00"),
            ("Autumn", dt.date(2026, 10, 20), "1500.00"),
            ("January", dt.date(2027, 1, 10), "1500.00"),
        ])

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(installment_ids, [row["id"] for row in response.data["installments"]],
                         "a published fee's installments are edited in place")
        self.assertEqual(
            [
                ("Tuition - April", "2026-04-10", "1000.00", "paid", None),
                # Cut to 500, it stays at the 700 paid - and, nothing being
                # left to pay, is settled (F3).
                ("Tuition - July", "2026-07-10", "700.00", "paid", None),
                ("Tuition - Autumn", "2026-10-20", "1500.00", "pending", None),
                ("Tuition - January", "2027-01-10", "1500.00", "pending", None),
            ],
            self.ledger(aarav),
        )
        entry = AuditLog.objects.filter(action="fee_dues.synced").order_by("id").last()
        self.assertEqual(("fee_structure", {"created": 0, "revived": 0, "cancelled": 0, "updated": 3}),
                         (entry.entity_type, entry.new_values))

    def test_a_part_paid_due_takes_a_higher_amount(self):
        aarav = self.student()
        structure = self.published(TUITION_8, school_class=self.class8)
        StudentFeeDue.objects.filter(student=aarav, label="Tuition - July").update(
            status=FeeDueStatus.PARTIAL, paid_amount="300.00"
        )

        self.put(structure, [TUITION_8[0], ("July", dt.date(2026, 7, 10), "1200.00"), *TUITION_8[2:]])

        self.assertEqual(Decimal("1200.00"), StudentFeeDue.objects.get(student=aarav, label="Tuition - July").amount)

    def test_an_added_installment_is_charged(self):
        aarav = self.student()
        structure = self.published(TUITION_8, school_class=self.class8)

        response = self.put(structure, [*TUITION_8, ("March", dt.date(2027, 3, 10), "1000.00")])

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(5, len(self.owing(aarav)))

    def test_removing_an_installment_students_are_charged_is_refused(self):
        self.student()
        structure = self.published(TUITION_8, school_class=self.class8)

        response = self.put(structure, TUITION_8[:2], amount="2000.00")

        self.assertEqual(422, response.status_code)
        self.assertEqual(
            ["Installment 3 already has students charged. Change its amount or date instead of removing it.",
             "Installment 4 already has students charged. Change its amount or date instead of removing it."],
            response.data["details"]["errors"]["installments"],
        )
        self.assertEqual(4, FeeInstallment.objects.filter(fee_structure=structure).count())
        self.assertEqual(Decimal("4000.00"), FeeStructure.objects.get(pk=structure.id).amount)

    def test_an_installment_charged_to_nobody_any_more_can_be_removed(self):
        aarav = self.student()
        structure = self.published(TUITION_8, school_class=self.class8)
        self.as_user(self.admin).patch(f"{STUDENTS}/{aarav.id}/deactivate")

        response = self.put(structure, TUITION_8[:3], amount="3000.00")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(3, FeeInstallment.objects.filter(fee_structure=structure).count())
        self.assertEqual(3, StudentFeeDue.objects.filter(student=aarav).count())

    def test_a_draft_is_still_replaced_wholesale(self):
        structure = self.fee(TUITION_8, school_class=self.class8)
        old = set(FeeInstallment.objects.filter(fee_structure=structure).values_list("id", flat=True))

        response = self.put(structure, TUITION_8[:2], amount="2000.00")

        self.assertEqual(200, response.status_code, response.data)
        self.assertFalse(old & set(FeeInstallment.objects.filter(fee_structure=structure).values_list("id", flat=True)))

    def test_a_fee_moved_after_a_late_joiner_joined_is_charged_to_them(self):
        late = self.student("Aarav", admission=dt.date(2026, 8, 1))
        structure = self.published(TUITION_8, school_class=self.class8)
        self.assertEqual(2, len(self.owing(late)))

        self.put(structure, [TUITION_8[0], ("July", dt.date(2026, 8, 10), "1000.00"), *TUITION_8[2:]])

        self.assertEqual(["Tuition - July", "Tuition - October", "Tuition - January"], self.owing(late))


# -- promotion ----------------------------------------------------------------


class Promotion(DuesTestCase):
    def test_promotion_charges_next_years_published_fees_and_graduation_cancels_what_is_left(self):
        next_year = factories.AcademicYearFactory(
            school=self.school, name="2027-28", start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31),
            is_current=False,
        )
        next_9 = factories.SchoolClassFactory(academic_year=next_year, name="Class 9", level=9)
        next_9_a = factories.ClassSectionFactory(school_class=next_9, name="A")
        moving = self.student("Aarav")
        finishing = self.student("Bina")
        self.published(TUITION_8, school_class=self.class8)
        self.published([("Annual", dt.date(2027, 4, 10), "5000.00")], school_class=next_9, year=next_year)

        response = self.as_user(self.admin).post("/api/v1/promotions", {
            "class_section_id": self.section8.id, "to_academic_year_id": next_year.id,
            "to_class_section_id": next_9_a.id,
            "outcomes": [{"student_id": moving.id, "outcome": "promote"},
                         {"student_id": finishing.id, "outcome": "graduate"}],
        }, format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(5, len(self.owing(moving)), "this year's four, still owed, and next year's one")
        self.assertEqual(1, StudentFeeDue.objects.filter(student=moving, academic_year=next_year).count())
        self.assertEqual(
            [("pending", None), ("pending", None), ("cancelled", "left"), ("cancelled", "left")],
            [(status, reason) for _, _, _, status, reason in self.ledger(finishing)],
        )
        entry = AuditLog.objects.get(action="fee_dues.synced", entity_type="promotion")
        self.assertEqual({"created": 1, "revived": 0, "cancelled": 2, "updated": 0}, entry.new_values)

    def test_a_student_who_left_in_the_enrollment_is_charged_nothing_more(self):
        aarav = self.student()
        self.published(TUITION_8, school_class=self.class8)
        StudentEnrollment.objects.filter(student=aarav).update(status=EnrollmentStatus.LEFT)

        FeeDueService.sync_student(aarav, self.year)

        self.assertEqual(["Tuition - April", "Tuition - July"], self.owing(aarav))


# -- idempotence --------------------------------------------------------------


class Idempotence(DuesTestCase):
    def test_a_second_reconcile_changes_nothing(self):
        aarav = self.student()
        StudentTransportAssignment.objects.create(
            school=self.school, student=aarav, route=self.route_a, transport_stop=self.stop_a
        )
        self.fee(TUITION_8, school_class=self.class8, status="published")
        self.fee(ROUTE_A, route=self.route_a, status="published")

        first = FeeDueService.sync_student(aarav, self.year)
        second = FeeDueService.sync_student(aarav, self.year)

        self.assertEqual({"created": 6, "revived": 0, "cancelled": 0, "updated": 0}, first.counts())
        self.assertEqual({"created": 0, "revived": 0, "cancelled": 0, "updated": 0}, second.counts())
        self.assertFalse(second.changed)

    def test_a_long_label_is_cut_to_the_column(self):
        head = FeeHead.objects.create(school=self.school, name="H" * 100)
        aarav = self.student()
        self.fee([("L" * 60, dt.date(2026, 10, 10), "10.00")], school_class=self.class8, head=head,
                 status="published")

        FeeDueService.sync_student(aarav, self.year)

        self.assertEqual(130, len(StudentFeeDue.objects.get(student=aarav).label))


# -- the repair command -------------------------------------------------------


class RepairCommand(DuesTestCase):
    def run_command(self, *args) -> str:
        out = io.StringIO()
        call_command("sync_fee_dues", *args, stdout=out)

        return out.getvalue()

    def test_it_charges_what_was_published_before_dues_existed_and_is_idempotent(self):
        aarav = self.student("Aarav")
        bina = self.student("Bina", section=self.section9)
        self.fee(TUITION_8, school_class=self.class8, status="published")
        self.fee(TUITION_9, school_class=self.class9, status="published")
        other_school = factories.SchoolFactory()
        other_year = factories.AcademicYearFactory(school=other_school)
        theirs = factories.StudentFactory(
            school=other_school,
            class_section=factories.ClassSectionFactory(
                school_class=factories.SchoolClassFactory(academic_year=other_year)
            ),
        )

        first = self.run_command("--school", str(self.school.id))

        self.assertIn("2026-27", first)
        self.assertIn("2 students enrolled; 6 dues created, 0 revived, 0 cancelled, 0 updated.", first)
        self.assertEqual(4, len(self.owing(aarav)))
        self.assertEqual(2, len(self.owing(bina)))
        self.assertEqual([], self.ledger(theirs))
        self.assertEqual(1, AuditLog.objects.filter(action="fee_dues.synced", entity_type="academic_year").count())

        second = self.run_command("--school", str(self.school.id), "--year", str(self.year.id))

        self.assertIn("0 dues created, 0 revived, 0 cancelled, 0 updated.", second)
        self.assertEqual(1, AuditLog.objects.filter(action="fee_dues.synced").count())

    def test_a_school_with_nothing_published_has_nothing_to_do(self):
        self.student()

        self.assertIn("Nothing to do", self.run_command("--school", str(self.school.id)))

    def test_an_unknown_school_or_year_is_an_error(self):
        from django.core.management import CommandError

        with self.assertRaises(CommandError):
            self.run_command("--school", "999999")

        with self.assertRaises(CommandError):
            self.run_command("--school", str(self.school.id), "--year", "999999")


# -- moving mid-year: from the day of the move (decided 2026-10-28) ---------------

MONTHLY_8 = [(month, dt.date(2026, number, 10), "1000.00")
             for month, number in (("July", 7), ("August", 8), ("September", 9), ("October", 10))]
MONTHLY_9 = [(f"{month} (9)", due, "1200.00") for month, due, _ in MONTHLY_8]
# 20:00 UTC on 19 August is already the 20th in Kolkata.
AUGUST_20 = dt.datetime(2026, 8, 19, 20, 0, tzinfo=dt.timezone.utc)
SEPTEMBER_15 = dt.datetime(2026, 9, 15, 6, 0, tzinfo=dt.timezone.utc)


def at(instant):
    return mock.patch("django.utils.timezone.now", return_value=instant)


class MovingFromTheDayOfTheMove(DuesTestCase):
    def pending_months(self, student) -> list[str]:
        """The due date of every line still owed - each once, or a month is
        being charged twice."""
        return [due for _, due, _, status, _ in self.ledger(student) if status != FeeDueStatus.CANCELLED]

    def test_a_class_move_charges_the_new_class_only_from_the_move_and_no_month_twice(self):
        aarav = self.student()
        self.published(MONTHLY_8, school_class=self.class8)
        self.published(MONTHLY_9, school_class=self.class9)

        with at(AUGUST_20):
            self.patch_student(aarav, {"class_section_id": self.section9.id})

        self.assertEqual(dt.date(2026, 8, 20),
                         StudentEnrollment.objects.get(student=aarav, academic_year=self.year).class_since,
                         "the school's date, not UTC's")
        self.assertEqual(
            [
                ("Tuition - July", "2026-07-10", "1000.00", "pending", None),
                ("Tuition - August", "2026-08-10", "1000.00", "pending", None),
                ("Tuition - September", "2026-09-10", "1000.00", "cancelled", "class_changed"),
                ("Tuition - September (9)", "2026-09-10", "1200.00", "pending", None),
                ("Tuition - October", "2026-10-10", "1000.00", "cancelled", "class_changed"),
                ("Tuition - October (9)", "2026-10-10", "1200.00", "pending", None),
            ],
            self.ledger(aarav),
        )
        months = self.pending_months(aarav)
        self.assertEqual(len(months), len(set(months)), "no month charged twice")

        with at(AUGUST_20):
            self.assertFalse(FeeDueService.sync_student(aarav, self.year).changed, "a second sync changes nothing")

    def test_moving_back_does_not_revive_what_fell_due_while_away(self):
        aarav = self.student()
        self.published(MONTHLY_8, school_class=self.class8)
        self.published(MONTHLY_9, school_class=self.class9)

        with at(AUGUST_20):
            self.patch_student(aarav, {"class_section_id": self.section9.id})
        with at(SEPTEMBER_15):
            self.patch_student(aarav, {"class_section_id": self.section8.id})

        self.assertEqual(dt.date(2026, 9, 15),
                         StudentEnrollment.objects.get(student=aarav, academic_year=self.year).class_since)
        self.assertEqual(
            [
                ("Tuition - July", "2026-07-10", "1000.00", "pending", None),
                ("Tuition - August", "2026-08-10", "1000.00", "pending", None),
                # September fell due in Class 9 and stays owed there; Class
                # 8's September stays cancelled.
                ("Tuition - September", "2026-09-10", "1000.00", "cancelled", "class_changed"),
                ("Tuition - September (9)", "2026-09-10", "1200.00", "pending", None),
                ("Tuition - October", "2026-10-10", "1000.00", "pending", None),
                ("Tuition - October (9)", "2026-10-10", "1200.00", "cancelled", "class_changed"),
            ],
            self.ledger(aarav),
        )
        months = self.pending_months(aarav)
        self.assertEqual(len(months), len(set(months)))

        with at(SEPTEMBER_15):
            self.assertFalse(FeeDueService.sync_student(aarav, self.year).changed)

    def test_a_route_change_charges_the_new_route_only_from_the_change(self):
        aarav = self.student()
        self.published([(m, d, "500.00") for m, d, _ in MONTHLY_8], route=self.route_a)
        self.published([(f"{m} (B)", d, "700.00") for m, d, _ in MONTHLY_8], route=self.route_b)

        self.ride(aarav, self.route_a, self.stop_a)
        self.assertIsNone(StudentTransportAssignment.objects.get(student=aarav).route_since,
                          "a first route follows the joining date")
        self.assertEqual(4, len(self.owing(aarav)), "from the joining date, July included")

        # Another stop on the same route is not a change of route.
        with at(AUGUST_20):
            self.ride(aarav, self.route_a, factories.TransportStopFactory(route=self.route_a))
        self.assertIsNone(StudentTransportAssignment.objects.get(student=aarav).route_since)

        with at(AUGUST_20):
            self.ride(aarav, self.route_b, self.stop_b)

        self.assertEqual(dt.date(2026, 8, 20), StudentTransportAssignment.objects.get(student=aarav).route_since)
        self.assertEqual(
            [
                ("Transport - July", "2026-07-10", "500.00", "pending", None),
                ("Transport - August", "2026-08-10", "500.00", "pending", None),
                ("Transport - September", "2026-09-10", "500.00", "cancelled", "route_changed"),
                ("Transport - September (B)", "2026-09-10", "700.00", "pending", None),
                ("Transport - October", "2026-10-10", "500.00", "cancelled", "route_changed"),
                ("Transport - October (B)", "2026-10-10", "700.00", "pending", None),
            ],
            self.ledger(aarav),
        )
        months = self.pending_months(aarav)
        self.assertEqual(len(months), len(set(months)))

        with at(AUGUST_20):
            self.assertFalse(FeeDueService.sync_student(aarav, self.year).changed)

    def test_admission_and_promotion_leave_class_since_empty(self):
        next_year = factories.AcademicYearFactory(
            school=self.school, name="2027-28", start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31),
            is_current=False,
        )
        next_9 = factories.SchoolClassFactory(academic_year=next_year, name="Class 9", level=9)
        next_9_a = factories.ClassSectionFactory(school_class=next_9, name="A")
        self.published([("Annual", dt.date(2027, 4, 10), "5000.00")], school_class=next_9, year=next_year)

        created = self.as_user(self.admin).post(STUDENTS, {
            "class_section_id": self.section8.id, "admission_number": "ADM-90", "first_name": "Hari",
            "last_name": "Menon", "guardian_name": "Lata Menon", "admission_date": "2026-04-01",
        }, format="json")
        self.assertEqual(201, created.status_code, created.data)
        hari = Student.objects.get(pk=created.data["id"])
        self.assertIsNone(StudentEnrollment.objects.get(student=hari, academic_year=self.year).class_since)

        response = self.as_user(self.admin).post("/api/v1/promotions", {
            "class_section_id": self.section8.id, "to_academic_year_id": next_year.id,
            "to_class_section_id": next_9_a.id, "outcomes": [{"student_id": hari.id, "outcome": "promote"}],
        }, format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertIsNone(StudentEnrollment.objects.get(student=hari, academic_year=next_year).class_since)
        self.assertEqual(1, StudentFeeDue.objects.filter(student=hari, academic_year=next_year).count())

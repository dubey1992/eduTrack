"""Students, over HTTP: the shape, the rules, and the isolation.

The isolation class at the bottom is the one that matters most. Each of those
is a school reading another school's records if the backend gets it wrong, and
a rewrite is exactly when that happens.
"""

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import StudentStatus, UserRole
from school.models import Student

from .test_scope import section_in


def ids_in(response) -> list[int]:
    """The student ids in a paginated response, in the order they arrived."""
    return [student["id"] for student in response.data["data"]]


def assign_a_bus(student, route_name: str, vehicle_name: str, stop_name: str):
    """Puts a student on a route, with plain rows.

    The transport factories come with the transport module at M11; this is
    here so the `transport` key on a student is exercised rather than left as
    a branch nothing has run.
    """
    from django.utils.timezone import now

    from school.models import (
        StudentTransportAssignment,
        TransportRoute,
        TransportStop,
        Vehicle,
    )

    school_id = student.school_id
    stamps = {"created_at": now(), "updated_at": now()}

    vehicle = Vehicle.objects.create(
        school_id=school_id,
        name=vehicle_name,
        registration_number="KA-01-" + vehicle_name[-2:],
        capacity=40,
        status="active",
        **stamps,
    )
    route = TransportRoute.objects.create(
        school_id=school_id, vehicle=vehicle, name=route_name, status="active", **stamps
    )
    stop = TransportStop.objects.create(
        school_id=school_id,
        route=route,
        name=stop_name,
        sequence_number=1,
        pickup_time="07:30",
        drop_time="15:30",
        **stamps,
    )

    return StudentTransportAssignment.objects.create(
        school_id=school_id, student=student, route=route, transport_stop=stop, **stamps
    )


class StudentApiTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.section = section_in(self.school)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def a_student(self, **overrides):
        overrides.setdefault("school", self.school)
        overrides.setdefault("class_section", self.section)

        return factories.StudentFactory(**overrides)

    def payload(self, **overrides) -> dict:
        body = {
            "school_id": self.school.id,
            "class_section_id": self.section.id,
            "admission_number": "ADM-2026-001",
            "first_name": "Zainab",
            "last_name": "Okafor",
            "guardian_name": "Nneka Okafor",
        }
        body.update(overrides)

        return body


class TheList(StudentApiTest):
    def test_it_is_paginated_with_the_meta_the_client_reads(self):
        self.a_student()

        response = self.client.get("/api/v1/students")

        self.assertEqual(200, response.status_code, response.data)
        self.assertIn("data", response.data)

        meta = response.data["meta"]
        for key in ("current_page", "last_page", "per_page", "total"):
            self.assertIn(key, meta, "the client cannot paginate without it")
            self.assertIsInstance(meta[key], int)

    def test_a_student_comes_back_whole(self):
        student = self.a_student()

        body = self.client.get("/api/v1/students").data["data"][0]

        for field in (
            "id", "school_id", "school_name", "class_section_id", "class_section_name",
            "admission_number", "first_name", "last_name", "name", "roll_number",
            "guardian_name", "guardian_mobile", "address", "status", "transport",
        ):
            self.assertIn(field, body)

        self.assertEqual(student.id, body["id"])
        self.assertEqual(self.school.name, body["school_name"])
        self.assertEqual(f"{student.first_name} {student.last_name}", body["name"])

    def test_a_student_who_does_not_ride_a_bus_has_transport_null(self):
        # Null, not a missing key. Laravel eager-loads the relation, so it
        # always sends this field; the client happens to read an absent key
        # the same way, but surviving a difference is not the same as not
        # having one.
        self.a_student()

        body = self.client.get("/api/v1/students").data["data"][0]

        self.assertIsNone(body["transport"])

    def test_a_student_who_rides_a_bus_carries_their_route_and_stop(self):
        # Transport is M11's work, but this key is part of the student's shape
        # today. Built with plain rows rather than factories because the
        # transport factories arrive with that module - and leaving the code
        # untested until then would mean shipping a branch nothing has run.
        student = self.a_student()
        assign_a_bus(student, route_name="Green Park", vehicle_name="Bus 04", stop_name="Rose Lane")

        body = self.client.get(f"/api/v1/students/{student.id}").data["transport"]

        self.assertEqual("Green Park", body["route_name"])
        self.assertEqual("Bus 04", body["vehicle_name"])
        self.assertEqual("Rose Lane", body["stop_name"])
        # "Bus 04 - Green Park": the vehicle and the route, as a driver says it.
        self.assertEqual("Bus 04 - Green Park", body["route_label"])

    def test_every_endpoint_answers_the_same_shape(self):
        # Whether a relation is loaded decides whether its key appears at all,
        # so a write path that forgot to reload would answer a different shape
        # from the list - and the client would store a student with no school
        # name until the next refresh.
        student = self.a_student()
        created = self.client.post("/api/v1/students", self.payload(), format="json")

        for where, body in (
            ("POST", created.data),
            ("GET one", self.client.get(f"/api/v1/students/{student.id}").data),
            ("PATCH", self.client.patch(
                f"/api/v1/students/{student.id}", {"first_name": "Edited"}, format="json"
            ).data),
            ("deactivate", self.client.patch(f"/api/v1/students/{student.id}/deactivate").data),
            ("list", self.client.get("/api/v1/students").data["data"][0]),
        ):
            with self.subTest(where=where):
                for field in ("school_name", "class_section_name", "transport"):
                    self.assertIn(field, body, where)

                self.assertEqual(self.school.name, body["school_name"], where)

    def test_the_class_section_name_is_the_class_and_the_section(self):
        # "Grade 8 A" - what a school calls it, not two ids the client would
        # have to join for itself.
        self.a_student()

        body = self.client.get("/api/v1/students").data["data"][0]

        self.assertEqual(
            f"{self.section.school_class.name} {self.section.name}",
            body["class_section_name"],
        )

    def test_per_page_is_honoured_and_capped(self):
        for index in range(3):
            self.a_student(admission_number=f"ADM-{index}")

        self.assertEqual(1, self.client.get("/api/v1/students?per_page=1").data["meta"]["per_page"])
        self.assertEqual(3, self.client.get("/api/v1/students?per_page=1").data["meta"]["total"])
        # Never an unbounded list, however the client asks (CLAUDE.md rule 12).
        self.assertEqual(100, self.client.get("/api/v1/students?per_page=5000").data["meta"]["per_page"])
        self.assertEqual(20, self.client.get("/api/v1/students?per_page=abc").data["meta"]["per_page"])

    def test_an_empty_list_still_paginates(self):
        response = self.client.get("/api/v1/students")

        self.assertEqual([], response.data["data"])
        self.assertEqual(0, response.data["meta"]["total"])
        self.assertEqual(1, response.data["meta"]["last_page"])
        self.assertIsNone(response.data["meta"]["from"])

    def test_the_search_ignores_case(self):
        # The difference crossing to PostgreSQL would otherwise have lost
        # silently: MySQL's collation is case-insensitive and PostgreSQL's is
        # not, so a plain LIKE means two different things.
        self.a_student(first_name="Aarav", last_name="Sharma")

        for term in ("aarav", "AARAV", "aAraV", "sharma"):
            with self.subTest(term=term):
                response = self.client.get("/api/v1/students?search=" + term)

                self.assertEqual(1, response.data["meta"]["total"], term)

    def test_the_search_also_matches_an_admission_number(self):
        self.a_student(admission_number="ADM-2026-042")

        response = self.client.get("/api/v1/students?search=2026-042")

        self.assertEqual(1, response.data["meta"]["total"])

    def test_the_list_filters_by_status(self):
        here = self.a_student(admission_number="A-1")
        gone = self.a_student(admission_number="A-2", status=StudentStatus.INACTIVE)

        active = self.client.get("/api/v1/students?status=active")
        inactive = self.client.get("/api/v1/students?status=inactive")

        self.assertEqual([here.id], ids_in(active))
        self.assertEqual([gone.id], ids_in(inactive))

    def test_the_list_filters_by_section(self):
        ours = self.a_student(admission_number="A-1")
        self.a_student(admission_number="A-3", class_section=section_in(self.school))

        response = self.client.get(f"/api/v1/students?class_section_id={self.section.id}")

        self.assertEqual([ours.id], ids_in(response))

    def test_a_role_with_no_student_access_is_refused(self):
        for role in (UserRole.HOD, UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role):
                client = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, client.get("/api/v1/students").status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get("/api/v1/students").status_code)


class ReadingOne(StudentApiTest):
    def test_one_student_comes_back(self):
        student = self.a_student()

        response = self.client.get(f"/api/v1/students/{student.id}")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(student.id, response.data["id"])

    def test_a_missing_student_is_404_in_the_standard_envelope(self):
        response = self.client.get("/api/v1/students/99999999")

        self.assertEqual(404, response.status_code, response.data)
        self.assertEqual("NOT_FOUND", response.data["code"])
        self.assertEqual({}, response.data["details"])


class Admitting(StudentApiTest):
    def test_a_student_is_created_and_returned_whole(self):
        response = self.client.post("/api/v1/students", self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Zainab", response.data["first_name"])
        self.assertEqual("active", response.data["status"])
        # The relations a write returns, which the client stores straight away.
        self.assertEqual(self.school.name, response.data["school_name"])
        self.assertIsNotNone(response.data["class_section_name"])

    def test_the_school_is_taken_from_the_account_not_the_request(self):
        # CLAUDE.md rule 10. The client may send whatever it likes.
        outsider = factories.SchoolFactory()

        response = self.client.post(
            "/api/v1/students", self.payload(school_id=outsider.id), format="json"
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])

    def test_a_missing_field_is_422_naming_it(self):
        response = self.client.post("/api/v1/students", {"first_name": "Nobody"}, format="json")

        self.assertEqual(422, response.status_code, response.data)
        errors = response.data["details"]["errors"]

        self.assertIn("admission_number", errors)
        self.assertEqual("The admission number field is required.", errors["admission_number"][0])

    def test_a_duplicate_admission_number_in_the_same_school_is_refused(self):
        self.client.post("/api/v1/students", self.payload(), format="json")

        response = self.client.post("/api/v1/students", self.payload(), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The admission number has already been taken.",
            response.data["details"]["errors"]["admission_number"][0],
        )

    def test_the_same_admission_number_in_another_school_is_fine(self):
        # Unique per school, not globally: two schools may each have an
        # ADM-001 and neither is wrong.
        self.client.post("/api/v1/students", self.payload(), format="json")

        elsewhere = factories.SchoolFactory()
        other_admin = factories.UserFactory(school=elsewhere, role=UserRole.SCHOOL_ADMIN)
        other_section = section_in(elsewhere)

        response = self.as_user(other_admin).post(
            "/api/v1/students",
            {
                "school_id": elsewhere.id,
                "class_section_id": other_section.id,
                "admission_number": "ADM-2026-001",
                "first_name": "Someone",
                "last_name": "Else",
                "guardian_name": "A Guardian",
            },
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_a_section_from_another_school_is_an_invalid_selection(self):
        # 422 on the field rather than 403: the client never had a legitimate
        # way to name it, so the honest answer is that the selection is wrong.
        elsewhere = factories.SchoolFactory()

        response = self.client.post(
            "/api/v1/students",
            self.payload(class_section_id=section_in(elsewhere).id),
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The selected class section id is invalid.",
            response.data["details"]["errors"]["class_section_id"][0],
        )

    def test_a_guardian_mobile_must_look_like_a_number(self):
        response = self.client.post(
            "/api/v1/students", self.payload(guardian_mobile="not a phone"), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The guardian mobile field format is invalid.",
            response.data["details"]["errors"]["guardian_mobile"][0],
        )

    def test_a_blank_optional_field_is_stored_as_nothing(self):
        # Laravel turns "" into null before any rule sees it, so a cleared
        # field passes `nullable` rather than failing a format rule.
        response = self.client.post(
            "/api/v1/students",
            self.payload(guardian_mobile="", roll_number="", address=""),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertIsNone(response.data["guardian_mobile"])
        self.assertIsNone(response.data["roll_number"])

    def test_a_name_that_is_a_number_is_refused(self):
        response = self.client.post("/api/v1/students", self.payload(first_name=123), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The first name field must be a string.",
            response.data["details"]["errors"]["first_name"][0],
        )

    def test_an_overlong_field_is_refused_with_the_limit_in_the_message(self):
        response = self.client.post(
            "/api/v1/students", self.payload(admission_number="x" * 31), format="json"
        )

        self.assertEqual(
            "The admission number field must not be greater than 30 characters.",
            response.data["details"]["errors"]["admission_number"][0],
        )

    def test_a_teacher_may_not_admit_a_student(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        response = self.as_user(teacher).post("/api/v1/students", self.payload(), format="json")

        self.assertEqual(403, response.status_code, response.data)
        self.assertEqual("FORBIDDEN", response.data["code"])


class Editing(StudentApiTest):
    def test_a_field_can_be_changed_on_its_own(self):
        student = self.a_student(first_name="Aarav")

        response = self.client.patch(
            f"/api/v1/students/{student.id}", {"first_name": "Renamed"}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("Renamed", response.data["first_name"])

        student.refresh_from_db()
        self.assertEqual("Renamed", student.first_name)

    def test_the_fields_not_sent_are_left_alone(self):
        student = self.a_student(first_name="Aarav", guardian_name="Meera Sharma")

        self.client.patch(f"/api/v1/students/{student.id}", {"first_name": "Renamed"}, format="json")

        student.refresh_from_db()
        self.assertEqual("Meera Sharma", student.guardian_name)

    def test_a_student_cannot_be_moved_to_another_school_by_editing(self):
        # school_id is fixed at creation, same as every other feature. The
        # field is not on the form at all, so sending it changes nothing.
        student = self.a_student()
        elsewhere = factories.SchoolFactory()

        response = self.client.patch(
            f"/api/v1/students/{student.id}", {"school_id": elsewhere.id}, format="json"
        )

        self.assertEqual(200, response.status_code, response.data)
        student.refresh_from_db()
        self.assertEqual(self.school.id, student.school_id)

    def test_taking_another_students_admission_number_is_refused(self):
        self.a_student(admission_number="ADM-1")
        student = self.a_student(admission_number="ADM-2")

        response = self.client.patch(
            f"/api/v1/students/{student.id}", {"admission_number": "ADM-1"}, format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("admission_number", response.data["details"]["errors"])

    def test_keeping_your_own_admission_number_is_not_a_duplicate(self):
        student = self.a_student(admission_number="ADM-1")

        response = self.client.patch(
            f"/api/v1/students/{student.id}",
            {"admission_number": "ADM-1", "first_name": "Renamed"},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)


class DeactivatingAndReinstating(StudentApiTest):
    def test_a_student_can_be_deactivated_and_activated_again(self):
        student = self.a_student()

        deactivated = self.client.patch(f"/api/v1/students/{student.id}/deactivate")
        self.assertEqual(200, deactivated.status_code, deactivated.data)
        self.assertEqual("inactive", deactivated.data["status"])

        activated = self.client.patch(f"/api/v1/students/{student.id}/activate")
        self.assertEqual("active", activated.data["status"])

    def test_deactivating_keeps_the_record(self):
        # A student who has left keeps their attendance, their reports and
        # their place in last year's register.
        student = self.a_student()

        self.client.patch(f"/api/v1/students/{student.id}/deactivate")

        self.assertTrue(Student.objects.filter(pk=student.id).exists())

    def test_a_teacher_may_not_deactivate_anybody(self):
        student = self.a_student()
        self.section.class_teacher_id = factories.UserFactory(
            school=self.school, role=UserRole.TEACHER
        ).id
        self.section.save()
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        response = self.as_user(teacher).patch(f"/api/v1/students/{student.id}/deactivate")

        self.assertEqual(403, response.status_code, response.data)


class SchoolIsolation(StudentApiTest):
    """The rules that matter more than any shape in this file."""

    def setUp(self):
        super().setUp()
        self.student = self.a_student()

        self.outside_school = factories.SchoolFactory()
        self.outsider = self.as_user(
            factories.UserFactory(school=self.outside_school, role=UserRole.SCHOOL_ADMIN)
        )

    def test_an_admin_cannot_read_another_schools_student(self):
        response = self.outsider.get(f"/api/v1/students/{self.student.id}")

        self.assertEqual(403, response.status_code, response.data)

    def test_an_admin_cannot_edit_another_schools_student(self):
        response = self.outsider.patch(
            f"/api/v1/students/{self.student.id}", {"first_name": "Stolen"}, format="json"
        )

        self.assertEqual(403, response.status_code, response.data)
        self.student.refresh_from_db()
        self.assertNotEqual("Stolen", self.student.first_name)

    def test_an_admin_cannot_deactivate_another_schools_student(self):
        response = self.outsider.patch(f"/api/v1/students/{self.student.id}/deactivate")

        self.assertEqual(403, response.status_code, response.data)
        self.student.refresh_from_db()
        self.assertEqual("active", self.student.status)

    def test_a_list_never_includes_another_schools_students(self):
        response = self.outsider.get("/api/v1/students")

        self.assertEqual([], [s for s in response.data["data"] if s["school_id"] == self.school.id])

    def test_a_school_id_in_the_query_string_does_not_widen_the_list(self):
        response = self.outsider.get(f"/api/v1/students?school_id={self.school.id}")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual([], [s for s in response.data["data"] if s["school_id"] == self.school.id])

    def test_a_teacher_sees_only_their_own_sections(self):
        mine = section_in(self.school)
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        mine.class_teacher_id = teacher.id
        mine.save()

        ours = self.a_student(class_section=mine, admission_number="MINE-1")

        response = self.as_user(teacher).get("/api/v1/students")

        self.assertEqual([ours.id], [s["id"] for s in response.data["data"]])

    def test_a_teacher_cannot_read_a_student_from_another_section(self):
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)

        response = self.as_user(teacher).get(f"/api/v1/students/{self.student.id}")

        self.assertEqual(403, response.status_code, response.data)


class AcrossAGroup(StudentApiTest):
    def setUp(self):
        super().setUp()
        self.group = factories.SchoolFactory()
        self.north = factories.SchoolFactory(parent_school=self.group)
        self.south = factories.SchoolFactory(parent_school=self.group)

        self.southern = factories.StudentFactory(
            school=self.south, class_section=section_in(self.south)
        )
        self.northern_admin = self.as_user(
            factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN)
        )

    def test_a_branch_admin_reads_a_sister_branchs_students(self):
        response = self.northern_admin.get(f"/api/v1/students/{self.southern.id}")

        self.assertEqual(200, response.status_code, response.data)

    def test_a_branch_admin_must_name_the_branch_when_admitting(self):
        # "My school" is ambiguous inside a group, so the form makes them say.
        response = self.northern_admin.post(
            "/api/v1/students",
            {
                "class_section_id": section_in(self.north).id,
                "admission_number": "GRP-1",
                "first_name": "Zainab",
                "last_name": "Okafor",
                "guardian_name": "Nneka Okafor",
            },
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The school id field is required.",
            response.data["details"]["errors"]["school_id"][0],
        )

    def test_a_branch_admin_may_admit_into_a_sister_branch(self):
        response = self.northern_admin.post(
            "/api/v1/students",
            {
                "school_id": self.south.id,
                "class_section_id": section_in(self.south).id,
                "admission_number": "GRP-2",
                "first_name": "Zainab",
                "last_name": "Okafor",
                "guardian_name": "Nneka Okafor",
            },
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.south.id, response.data["school_id"])

    def test_a_branch_admin_may_not_admit_into_a_school_outside_the_group(self):
        response = self.northern_admin.post(
            "/api/v1/students",
            {
                "school_id": self.school.id,
                "class_section_id": self.section.id,
                "admission_number": "GRP-3",
                "first_name": "Zainab",
                "last_name": "Okafor",
                "guardian_name": "Nneka Okafor",
            },
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The selected school id is invalid.",
            response.data["details"]["errors"]["school_id"][0],
        )
        self.assertFalse(Student.objects.filter(admission_number="GRP-3").exists())

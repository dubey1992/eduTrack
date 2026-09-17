"""Bulk upload of staff, subjects, vehicles and drivers, over HTTP.

The student importer has its own file; the reading of the file - headings,
blank lines, the all-or-nothing rule - is shared and tested there. These are
about what each of the other four spreadsheets checks and creates, and the two
things a spreadsheet does that a form does not: it names things rather than
picking ids, and it capitalises however the person typing felt like.
"""

import datetime as dt

from django.core.cache import cache
from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, hashing, tokens
from school.enums import UserRole
from school.models import Driver, StaffProfile, Subject, User, Vehicle

STAFF_HEADINGS = "employee_id,first_name,last_name,email,mobile,role,department,designation,joining_date,address"
SUBJECT_HEADINGS = "code,name,department,min_class_level,max_class_level,lead_teacher_email"


def staff_row(**overrides) -> str:
    row = {
        "employee_id": "EMP-1",
        "first_name": "Priya",
        "last_name": "Nair",
        "email": "priya.nair@example.com",
        "mobile": '"+91 98765 43210"',
        "role": "TEACHER",
        "department": "Science",
        "designation": "Senior Teacher",
        "joining_date": "09/14/2026",
        "address": "22 Hill Road",
    }
    row.update(overrides)

    return ",".join(row.values())


class ImporterTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.science = factories.DepartmentFactory(school=self.school, name="Science")
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def upload(self, kind: str, headings: str, *rows: str, client=None):
        body = "\r\n".join([headings, *rows]) + "\r\n"
        file = SimpleUploadedFile(f"{kind}.csv", body.encode("utf-8"), content_type="text/csv")

        return (client or self.client).post(f"/api/v1/imports/{kind}", {"file": file}, format="multipart")

    def refused(self, response) -> list[list[str]]:
        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("BULK_IMPORT_FAILED", response.data["code"])

        return [row["messages"] for row in response.data["details"]["rows"]]


class TheTemplates(ImporterTest):
    def assertTemplate(self, kind: str, expected: str):
        response = self.client.get(f"/api/v1/imports/{kind}/template")

        self.assertEqual(200, response.status_code)
        self.assertIn(f'filename="{kind}-template.csv"', response["Content-Disposition"])
        # Byte for byte what Laravel's fputcsv wrote: a byte order mark, a
        # field with a space in it quoted, and "\n" line endings.
        self.assertEqual(("﻿" + expected).encode("utf-8"), response.content)

    def test_the_staff_template(self):
        self.assertTemplate(
            "staff",
            STAFF_HEADINGS + "\n"
            'EMP-1042,Priya,Nair,priya.nair@example.com,"+91 98765 43210",TEACHER,Science,'
            '"Senior Teacher",09/14/2026,"22 Hill Road, Pune"\n',
        )

    def test_the_subjects_template(self):
        self.assertTemplate("subjects", SUBJECT_HEADINGS + "\nSCI-05,Science,Science,5,8,priya.nair@example.com\n")

    def test_the_vehicles_template(self):
        self.assertTemplate("vehicles", 'name,registration_number,capacity\n"Bus 12","MH 12 AB 3456",42\n')

    def test_the_drivers_template(self):
        self.assertTemplate(
            "drivers",
            'name,mobile,licence_number,licence_expiry\n"Ramesh Yadav","+91 98765 43210",MH1220260001234,09/14/2029\n',
        )

    def test_a_teacher_cannot_even_see_the_staff_template(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, teacher.get("/api/v1/imports/staff/template").status_code)


class StaffImport(ImporterTest):
    def test_each_row_gets_a_generated_password_that_must_be_changed(self):
        response = self.upload("staff", STAFF_HEADINGS, staff_row())

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual((1, "Teachers and Staff"), (response.data["imported"], response.data["label"]))

        detail = response.data["details"][0]
        user = User.objects.get(email="priya.nair@example.com")
        profile = StaffProfile.objects.get(user=user)

        self.assertEqual(
            {"id": user.id, "name": "Priya Nair", "email": "priya.nair@example.com"},
            {key: detail[key] for key in ("id", "name", "email")},
        )
        self.assertTrue(hashing.check(detail["temporary_password"], user.password))
        self.assertTrue(user.must_change_password)
        self.assertEqual((UserRole.TEACHER, self.school.id), (user.role, user.school_id))
        self.assertEqual(
            ("EMP-1", self.science.id, dt.date(2026, 9, 14), self.school.id),
            (profile.employee_id, profile.department_id, profile.joining_date, profile.school_id),
        )

    def test_the_password_is_long_and_mixes_letters_numbers_and_symbols(self):
        passwords = [
            self.upload("staff", STAFF_HEADINGS, staff_row(employee_id=f"EMP-{n}", email=f"p{n}@example.com"))
            .data["details"][0]["temporary_password"]
            for n in range(3)
        ]

        self.assertEqual(3, len(set(passwords)))
        for password in passwords:
            self.assertEqual(14, len(password))
            self.assertTrue(any(c.isalpha() for c in password))
            self.assertTrue(any(c.isdigit() for c in password))
            self.assertTrue(any(not c.isalnum() for c in password))

    def test_an_address_with_capitals_is_stored_lowercase_and_signs_in(self):
        response = self.upload("staff", STAFF_HEADINGS, staff_row(email="Priya.Nair@Example.com"))

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("priya.nair@example.com", response.data["details"][0]["email"])

        login = APIClient().post(
            "/api/v1/auth/login",
            {"email": "Priya.Nair@Example.com", "password": response.data["details"][0]["temporary_password"]},
            format="json",
        )
        self.assertEqual(200, login.status_code, login.data)

    def test_a_role_and_a_department_are_read_however_they_are_capitalised(self):
        response = self.upload("staff", STAFF_HEADINGS, staff_row(role="Transport_Manager", department="SCIENCE"))

        self.assertEqual(201, response.status_code, response.data)
        user = User.objects.get(email="priya.nair@example.com")
        self.assertEqual(UserRole.TRANSPORT_MANAGER, user.role)
        self.assertEqual(self.science.id, user.staff_profile.department_id)

    def test_a_joining_date_without_leading_zeros_still_reads(self):
        self.assertEqual(201, self.upload("staff", STAFF_HEADINGS, staff_row(joining_date="9/4/2026")).status_code)
        self.assertEqual(dt.date(2026, 9, 4), StaffProfile.objects.get(employee_id="EMP-1").joining_date)

    def test_a_blank_department_mobile_and_address_are_fine(self):
        response = self.upload("staff", STAFF_HEADINGS, staff_row(mobile="", department="", designation="", address=""))

        self.assertEqual(201, response.status_code, response.data)
        profile = StaffProfile.objects.get(employee_id="EMP-1")
        self.assertEqual((None, None, None), (profile.department_id, profile.designation, profile.address))

    def test_every_problem_on_a_row_is_reported(self):
        messages = self.refused(
            self.upload(
                "staff",
                STAFF_HEADINGS,
                staff_row(
                    employee_id="E" * 31, first_name="", email="nope", mobile="98765", role="PRINCIPAL",
                    department="Art", joining_date="14/09/2026",
                ),
            )
        )

        self.assertEqual(
            [[
                "The employee id field must not be greater than 30 characters.",
                "The first name field is required.",
                "The email field must be a valid email address.",
                "The mobile field format is invalid.",
                "The role must be one of: HOD, TEACHER, STAFF, TRANSPORT_MANAGER, ACCOUNTANT.",
                "The selected department is invalid.",
                "The joining date field must match the format m/d/Y.",
            ]],
            messages,
        )
        self.assertEqual(0, User.objects.filter(email="nope").count())

    def test_an_import_cannot_create_an_admin_account(self):
        self.refused(self.upload("staff", STAFF_HEADINGS, staff_row(role="SCHOOL_ADMIN")))

        self.assertFalse(User.objects.filter(email="priya.nair@example.com").exists())

    def test_an_address_in_use_anywhere_is_taken_however_it_is_capitalised(self):
        factories.UserFactory(email="priya.nair@example.com", school=factories.SchoolFactory())

        for email in ("priya.nair@example.com", "Priya.Nair@EXAMPLE.com"):
            self.assertEqual(
                [["The email has already been taken."]],
                self.refused(self.upload("staff", STAFF_HEADINGS, staff_row(email=email))),
            )

    def test_an_employee_id_is_taken_only_within_the_school(self):
        factories.StaffProfileFactory(employee_id="EMP-1", user__school=self.school)
        factories.StaffProfileFactory(employee_id="EMP-2", user__school=factories.SchoolFactory())

        self.assertEqual(
            [["The employee id has already been taken."]],
            self.refused(self.upload("staff", STAFF_HEADINGS, staff_row())),
        )
        self.assertEqual(201, self.upload("staff", STAFF_HEADINGS, staff_row(employee_id="EMP-2")).status_code)

    def test_the_same_address_twice_in_one_file_is_caught(self):
        messages = self.refused(
            self.upload(
                "staff",
                STAFF_HEADINGS,
                staff_row(),
                staff_row(employee_id="EMP-2", email="PRIYA.NAIR@example.com"),
            )
        )

        self.assertEqual([['The email "PRIYA.NAIR@example.com" is also on row 2.']], messages)
        self.assertEqual(0, StaffProfile.objects.count())

    def test_a_department_at_another_school_is_not_a_department(self):
        other = factories.SchoolFactory()
        factories.DepartmentFactory(school=other, name="Music")

        self.assertEqual(
            [["The selected department is invalid."]],
            self.refused(self.upload("staff", STAFF_HEADINGS, staff_row(department="Music"))),
        )


class SubjectImport(ImporterTest):
    def setUp(self):
        super().setUp()
        self.lead = factories.UserFactory(school=self.school, role=UserRole.TEACHER, email="lead@example.com")

    def test_a_subject_is_filed_under_its_department_and_lead(self):
        response = self.upload("subjects", SUBJECT_HEADINGS, "SCI-05,General Science,SCIENCE,5,8,Lead@Example.com")

        self.assertEqual(201, response.status_code, response.data)
        subject = Subject.objects.get(code="SCI-05")
        self.assertEqual([{"id": subject.id, "name": "General Science"}], response.data["details"])
        self.assertEqual(
            (self.school.id, self.science.id, self.lead.id, 5, 8),
            (subject.school_id, subject.department_id, subject.lead_teacher_id, subject.min_class_level, subject.max_class_level),
        )

    def test_the_lead_teacher_is_optional(self):
        self.assertEqual(201, self.upload("subjects", SUBJECT_HEADINGS, "SCI-05,Science,Science,5,8,").status_code)
        self.assertIsNone(Subject.objects.get(code="SCI-05").lead_teacher_id)

    def test_a_class_range_that_runs_backwards_is_refused(self):
        self.assertEqual(
            [["The max class level must be at or above the min class level."]],
            self.refused(self.upload("subjects", SUBJECT_HEADINGS, "SCI-05,Science,Science,8,5,")),
        )
        self.assertEqual(0, Subject.objects.count())

    def test_class_levels_must_be_whole_numbers_from_0_to_12(self):
        self.assertEqual(
            [
                ["The min class level field must be an integer.", "The max class level field must be at least 0."],
                ["The max class level field must not be greater than 12."],
            ],
            self.refused(
                self.upload("subjects", SUBJECT_HEADINGS, "SCI-05,Science,Science,abc,-1,", "SCI-06,Science,Science,1,13,")
            ),
        )

    def test_a_lead_at_another_school_in_another_role_or_not_an_address_is_refused(self):
        factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.TEACHER, email="elsewhere@example.com")
        factories.UserFactory(school=self.school, role=UserRole.STAFF, email="clerk@example.com")

        messages = self.refused(
            self.upload(
                "subjects",
                SUBJECT_HEADINGS,
                "SCI-05,Science,Science,5,8,Elsewhere@example.com",
                "SCI-06,Science,Science,5,8,clerk@example.com",
                "SCI-07,Science,Science,5,8,not-an-address",
            )
        )

        self.assertEqual(
            [
                ["The selected lead teacher email is invalid."],
                ["The selected lead teacher email is invalid."],
                ["The lead teacher email field must be a valid email address."],
            ],
            messages,
        )

    def test_a_code_is_taken_only_within_the_school(self):
        factories.SubjectFactory(school=self.school, code="SCI-05")
        factories.SubjectFactory(school=factories.SchoolFactory(), code="SCI-06")

        self.assertEqual(
            [["The code has already been taken."]],
            self.refused(self.upload("subjects", SUBJECT_HEADINGS, "SCI-05,Science,Science,5,8,")),
        )
        self.assertEqual(201, self.upload("subjects", SUBJECT_HEADINGS, "SCI-06,Science,Science,5,8,").status_code)


class VehicleAndDriverImport(ImporterTest):
    def test_a_school_admin_imports_vehicles(self):
        response = self.upload("vehicles", "name,registration_number,capacity", "Bus 12,MH 12 AB 3456,42")

        self.assertEqual(201, response.status_code, response.data)
        vehicle = Vehicle.objects.get(registration_number="MH 12 AB 3456")
        self.assertEqual((self.school.id, "Bus 12", 42), (vehicle.school_id, vehicle.name, vehicle.capacity))
        self.assertEqual([{"id": vehicle.id, "name": "Bus 12"}], response.data["details"])

    def test_an_impossible_capacity_stops_the_file(self):
        messages = self.refused(
            self.upload(
                "vehicles",
                "name,registration_number,capacity",
                "Bus 1,REG-1,many",
                "Bus 2,REG-2,0",
                "Bus 3,REG-3,201",
            )
        )

        self.assertEqual(
            [
                ["The capacity field must be an integer."],
                ["The capacity field must be at least 1."],
                ["The capacity field must not be greater than 200."],
            ],
            messages,
        )
        self.assertEqual(0, Vehicle.objects.count())

    def test_a_registration_already_in_the_school_is_taken(self):
        factories.VehicleFactory(school=self.school, registration_number="REG-1")

        self.assertEqual(
            [["The registration number has already been taken."]],
            self.refused(self.upload("vehicles", "name,registration_number,capacity", "Bus 1,REG-1,40")),
        )

    def test_a_school_admin_imports_drivers(self):
        response = self.upload(
            "drivers", "name,mobile,licence_number,licence_expiry", "Ramesh Yadav,+91 98765 43210,DL-1,9/14/2029"
        )

        self.assertEqual(201, response.status_code, response.data)
        driver = Driver.objects.get(licence_number="DL-1")
        self.assertEqual(
            (self.school.id, "Ramesh Yadav", "+91 98765 43210", dt.date(2029, 9, 14)),
            (driver.school_id, driver.name, driver.mobile, driver.licence_expiry),
        )

    def test_a_driver_without_a_mobile_or_expiry_is_fine(self):
        response = self.upload("drivers", "name,mobile,licence_number,licence_expiry", "Ramesh Yadav,,DL-1,")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual((None, None), tuple(Driver.objects.values_list("mobile", "licence_expiry").get()))

    def test_a_bad_driver_row_says_everything_wrong_with_it(self):
        factories.DriverFactory(school=self.school, licence_number="DL-1")

        messages = self.refused(
            self.upload("drivers", "name,mobile,licence_number,licence_expiry", ",98765,DL-1,2029-09-14")
        )

        self.assertEqual(
            [[
                "The name field is required.",
                "The mobile field format is invalid.",
                "The licence number has already been taken.",
                "The licence expiry field must match the format m/d/Y.",
            ]],
            messages,
        )


class ImportAccess(ImporterTest):
    def test_the_rows_land_in_the_actors_school_whatever_the_request_says(self):
        outsider = factories.SchoolFactory()
        body = "name,registration_number,capacity\r\nBus 1,REG-1,40\r\n"

        response = self.client.post(
            "/api/v1/imports/vehicles",
            {"file": SimpleUploadedFile("v.csv", body.encode(), content_type="text/csv"), "school_id": outsider.id},
            format="multipart",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, Vehicle.objects.get().school_id)

    def test_a_super_admin_imports_into_the_school_they_name(self):
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))
        body = "name,registration_number,capacity\r\nBus 1,REG-1,40\r\n"

        response = root.post(
            "/api/v1/imports/vehicles",
            {"file": SimpleUploadedFile("v.csv", body.encode(), content_type="text/csv"), "school_id": self.school.id},
            format="multipart",
        )

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, Vehicle.objects.get().school_id)

    def test_only_admins_import_any_of_the_four(self):
        # A transport manager runs the fleet but does not add to it in bulk;
        # an HOD leads staff but does not hire them.
        for role in (UserRole.TEACHER, UserRole.HOD, UserRole.STAFF, UserRole.TRANSPORT_MANAGER, UserRole.ACCOUNTANT):
            client = self.as_user(factories.UserFactory(school=self.school, role=role))

            for kind, headings, row in (
                ("staff", STAFF_HEADINGS, staff_row()),
                ("subjects", SUBJECT_HEADINGS, "SCI-05,Science,Science,5,8,"),
                ("vehicles", "name,registration_number,capacity", "Bus 1,REG-1,40"),
                ("drivers", "name,mobile,licence_number,licence_expiry", "Ramesh,,DL-1,"),
            ):
                with self.subTest(role=role, kind=kind):
                    self.assertEqual(403, self.upload(kind, headings, row, client=client).status_code)

        self.assertEqual(
            (0, 0, 0, 0),
            (StaffProfile.objects.count(), Subject.objects.count(), Vehicle.objects.count(), Driver.objects.count()),
        )

    def test_importing_needs_a_signed_in_account(self):
        self.assertEqual(401, self.upload("staff", STAFF_HEADINGS, staff_row(), client=APIClient()).status_code)


class AddressesAreStoredLowercase(TestCase):
    def test_saving_a_user_lowercases_and_trims_the_address(self):
        user = factories.UserFactory(email="  Mixed.Case@Example.COM ")

        user.refresh_from_db()
        self.assertEqual("mixed.case@example.com", user.email)

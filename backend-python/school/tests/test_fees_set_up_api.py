"""Fee Set-up over HTTP (docs/fees.md, F1): fee heads, class and bus route fees
with their installments, publishing, the installment-plan helper, and who may
do any of it. The arithmetic alone is test_fees_plan.py.

The academic year throughout is 2026-27: 1 April 2026 to 31 March 2027.
"""

import datetime as dt

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import AuditLog, FeeHead, FeeInstallment, FeeStructure, ModuleSetting, RolePermission

HEADS = "/api/v1/fees/heads"
STRUCTURES = "/api/v1/fees/structures"
PUBLISH_ALL = "/api/v1/fees/structures/publish"
PLAN = "/api/v1/fees/installment-plan"


def two_installments(first="6000.00", second="6000.00"):
    return [
        {"label": "First half", "due_date": "2026-04-10", "amount": first},
        {"label": "Second half", "due_date": "2026-10-10", "amount": second},
    ]


class FeesTestCase(TestCase):
    def setUp(self):
        cache.clear()

        self.school = factories.SchoolFactory(name="Sunrise Public School", currency_code="INR")
        self.grant(self.school)
        self.year = factories.AcademicYearFactory(
            school=self.school, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.class8 = factories.SchoolClassFactory(academic_year=self.year, name="Class 8", level=8)
        self.class2 = factories.SchoolClassFactory(academic_year=self.year, name="Class 2", level=2)
        self.route = factories.TransportRouteFactory(school=self.school, name="Route A")

        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.accountant = factories.UserFactory(school=self.school, role=UserRole.ACCOUNTANT)
        self.root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        # Another school, with fees of its own, that nobody above may touch.
        self.other = factories.SchoolFactory(name="Hillside Academy", currency_code="USD")
        self.grant(self.other)
        self.other_year = factories.AcademicYearFactory(
            school=self.other, name="2026-27", start_date=dt.date(2026, 4, 1), end_date=dt.date(2027, 3, 31)
        )
        self.other_class = factories.SchoolClassFactory(academic_year=self.other_year, name="Class 8", level=8)
        self.other_route = factories.TransportRouteFactory(school=self.other, name="Route Z")
        self.other_admin = factories.UserFactory(school=self.other, role=UserRole.SCHOOL_ADMIN)

    # -- helpers ------------------------------------------------------------

    @staticmethod
    def grant(school, **switches):
        return factories.ModuleSettingFactory(school=school, module="fees", **switches)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def head(self, name="Tuition", school=None, **fields):
        return FeeHead.objects.create(school=school or self.school, name=name, **fields)

    def transport(self, school=None):
        return FeeHead.objects.get_or_create(
            school=school or self.school, name="Transport", defaults={"is_transport": True}
        )[0]

    def class_fee(self, client=None, **overrides):
        body = {
            "academic_year_id": self.year.id,
            "school_class_id": self.class8.id,
            "fee_head_id": overrides.pop("fee_head_id", None) or self.head_id("Tuition"),
            "amount": "12000.00",
            "frequency": "yearly",
            "installments": two_installments(),
            **overrides,
        }

        return (client or self.as_user(self.accountant)).post(STRUCTURES, body, format="json")

    def route_fee(self, client=None, **overrides):
        body = {
            "academic_year_id": self.year.id,
            "transport_route_id": self.route.id,
            "fee_head_id": self.transport().id,
            "amount": "12000.00",
            "frequency": "yearly",
            "installments": two_installments(),
            **overrides,
        }

        return (client or self.as_user(self.accountant)).post(STRUCTURES, body, format="json")

    def head_id(self, name: str) -> int:
        found = FeeHead.objects.filter(school=self.school, name=name).first()

        return (found or self.head(name)).id

    def created(self, response) -> dict:
        self.assertEqual(201, response.status_code, response.data)

        return response.data

    def errors(self, response) -> dict:
        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("VALIDATION_ERROR", response.data["code"])

        return response.data["details"]["errors"]

    def other_structure(self):
        head = self.head("Tuition", school=self.other)

        return FeeStructure.objects.create(
            school=self.other, academic_year=self.other_year, school_class=self.other_class, fee_head=head,
            amount="500.00", currency_code="USD", frequency="yearly", status="draft",
        )


# -- who may do what ------------------------------------------------------------


class WhoMayDoWhat(FeesTestCase):
    def every_endpoint(self, structure_id: int, head_id: int):
        """(method, url, body) for every fee endpoint - reads, then writes."""
        reads = [
            ("get", HEADS, None),
            ("get", f"{STRUCTURES}?academic_year_id={self.year.id}", None),
            ("get", f"{STRUCTURES}/{structure_id}", None),
            ("get", f"{PLAN}?academic_year_id={self.year.id}&frequency=yearly&amount=100", None),
        ]
        writes = [
            ("post", HEADS, {"name": "Library"}),
            ("patch", f"{HEADS}/{head_id}", {"name": "Library 2"}),
            ("delete", f"{HEADS}/{head_id}", None),
            ("post", STRUCTURES, {"academic_year_id": self.year.id, "school_class_id": self.class2.id,
                                  "fee_head_id": head_id, "amount": "100", "frequency": "yearly",
                                  "installments": [{"label": "A", "due_date": "2026-04-10", "amount": "100"}]}),
            ("put", f"{STRUCTURES}/{structure_id}", {"amount": "12000", "frequency": "yearly",
                                                    "installments": two_installments()}),
            ("post", f"{STRUCTURES}/{structure_id}/publish", None),
            ("post", PUBLISH_ALL, {"academic_year_id": self.year.id}),
            ("delete", f"{STRUCTURES}/{structure_id}", None),
        ]

        return reads, writes

    def call(self, client, method, url, body):
        return getattr(client, method)(url, body, format="json") if body is not None else getattr(client, method)(url)

    def make_fee_and_head(self):
        structure_id = self.created(self.class_fee())["id"]
        spare = self.head("Spare")

        return structure_id, spare.id

    def test_school_admin_and_accountant_may_do_everything(self):
        for user in (self.admin, self.accountant):
            with self.subTest(role=user.role):
                FeeInstallment.objects.all().delete()
                FeeStructure.objects.all().delete()
                FeeHead.objects.filter(is_transport=False).delete()
                structure_id, head_id = self.make_fee_and_head()
                reads, writes = self.every_endpoint(structure_id, head_id)
                client = self.as_user(user)

                for method, url, body in reads:
                    self.assertEqual(200, self.call(client, method, url, body).status_code, url)

                expected = [201, 200, 204, 409, 200, 200, 200, 409]
                # The head is deleted before a structure is made with it, so
                # that POST is refused (422) - asked separately below.
                writes[3] = ("post", STRUCTURES, {
                    "academic_year_id": self.year.id, "school_class_id": self.class2.id,
                    "fee_head_id": self.head("Exam").id, "amount": "100", "frequency": "yearly",
                    "installments": [{"label": "A", "due_date": "2026-04-10", "amount": "100"}],
                })
                expected[3] = 201

                for (method, url, body), status in zip(writes, expected):
                    response = self.call(client, method, url, body)
                    self.assertEqual(status, response.status_code, (method, url, response.data))

    def test_every_other_role_is_refused_everything_by_default(self):
        structure_id, head_id = self.make_fee_and_head()
        reads, writes = self.every_endpoint(structure_id, head_id)

        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.TRANSPORT_MANAGER,
                     UserRole.DRIVER, UserRole.BUS_ATTENDANT):
            client = self.as_user(factories.UserFactory(school=self.school, role=role))

            for method, url, body in reads + writes:
                with self.subTest(role=role, method=method, url=url):
                    response = self.call(client, method, url, body)
                    self.assertEqual(403, response.status_code, response.data)
                    self.assertEqual("FORBIDDEN", response.data["code"])

        self.assertEqual(1, FeeStructure.objects.filter(school=self.school).count())
        self.assertTrue(FeeHead.objects.filter(pk=head_id).exists())

    def test_nobody_signed_in_is_asked_to_sign_in(self):
        structure_id, head_id = self.make_fee_and_head()
        reads, writes = self.every_endpoint(structure_id, head_id)

        for method, url, body in reads + writes:
            with self.subTest(method=method, url=url):
                self.assertEqual(401, self.call(APIClient(), method, url, body).status_code)

    def test_a_super_admin_reads_every_school_and_changes_nothing(self):
        structure_id, head_id = self.make_fee_and_head()
        reads, writes = self.every_endpoint(structure_id, head_id)
        client = self.as_user(self.root)

        self.assertEqual(200, client.get(HEADS, {"school_id": self.school.id}).status_code)
        for method, url, body in reads:
            self.assertEqual(200, self.call(client, method, url, body).status_code, url)

        for method, url, body in writes:
            with self.subTest(method=method, url=url):
                body = {**body, "school_id": self.school.id} if isinstance(body, dict) else body
                self.assertEqual(403, self.call(client, method, url, body).status_code)

        self.assertEqual("draft", FeeStructure.objects.get(pk=structure_id).status)
        self.assertTrue(FeeHead.objects.filter(pk=head_id).exists())

    def test_a_super_admin_naming_no_school_reads_every_school_with_fees_on(self):
        self.head("Tuition")
        self.head("Uniform", school=self.other)
        dark = factories.SchoolFactory()
        self.head("Hidden", school=dark)

        data = self.as_user(self.root).get(HEADS).data["data"]

        self.assertEqual(
            [(self.school.id, "Transport"), (self.school.id, "Tuition"), (self.other.id, "Transport"),
             (self.other.id, "Uniform")],
            [(row["school_id"], row["name"]) for row in data],
        )
        self.assertFalse(FeeHead.objects.filter(school=dark, is_transport=True).exists(),
                         "no Transport head is made for a school without fees")

    def test_a_super_admin_naming_a_school_without_fees_is_told_it_is_off(self):
        dark = factories.SchoolFactory()

        response = self.as_user(self.root).get(HEADS, {"school_id": dark.id})

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])
        self.assertEqual(404, self.as_user(self.root).get(HEADS, {"school_id": 999999}).status_code)

    def test_a_group_admin_works_across_their_group_and_nowhere_else(self):
        branch = factories.SchoolFactory(parent_school=self.school, name="Sunrise North")
        self.grant(branch)
        branch_year = factories.AcademicYearFactory(school=branch, name="2026-27")
        branch_class = factories.SchoolClassFactory(academic_year=branch_year, name="Class 1", level=1)
        group_admin = factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN)
        client = self.as_user(group_admin)

        # In scope: names the school, and it lands there.
        self.assertEqual(422, client.post(HEADS, {"name": "Tuition"}, format="json").status_code,
                         "a group spans schools, so the school must be named")
        head = self.created(client.post(HEADS, {"name": "Tuition", "school_id": branch.id}, format="json"))
        self.assertEqual(branch.id, head["school_id"])
        structure = self.created(client.post(STRUCTURES, {
            "academic_year_id": branch_year.id, "school_class_id": branch_class.id, "fee_head_id": head["id"],
            "amount": "100", "frequency": "yearly",
            "installments": [{"label": "A", "due_date": "2026-04-10", "amount": "100"}],
        }, format="json"))
        self.assertEqual(200, client.post(f"{STRUCTURES}/{structure['id']}/publish").status_code)
        self.assertEqual({self.school.id, branch.id},
                         {row["school_id"] for row in client.get(HEADS).data["data"]})
        self.assertEqual({branch.id}, {row["school_id"] for row in client.get(HEADS, {"school_id": branch.id}).data["data"]})

        # Out of scope: another school's records and ids.
        theirs = self.other_structure()
        self.assertEqual(403, client.get(f"{STRUCTURES}/{theirs.id}").status_code)
        self.assertEqual(403, client.post(f"{STRUCTURES}/{theirs.id}/publish").status_code)
        self.assertEqual(403, client.patch(f"{HEADS}/{theirs.fee_head_id}", {"name": "Mine"}, format="json").status_code)
        self.assertIn("school_id", self.errors(client.post(HEADS, {"name": "X", "school_id": self.other.id}, format="json")))
        self.assertIn("academic_year_id", self.errors(client.get(STRUCTURES, {"academic_year_id": self.other_year.id})))
        self.assertNotIn(self.other.id, {row["school_id"] for row in client.get(HEADS, {"school_id": self.other.id}).data["data"]})

    def test_a_widened_matrix_lets_a_teacher_read_fees_and_still_not_write_them(self):
        structure_id, head_id = self.make_fee_and_head()
        RolePermission.objects.create(role="TEACHER", module="fees", level="view")
        reads, writes = self.every_endpoint(structure_id, head_id)
        client = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        for method, url, body in reads:
            self.assertEqual(200, self.call(client, method, url, body).status_code, url)

        for method, url, body in writes:
            with self.subTest(method=method, url=url):
                self.assertEqual(403, self.call(client, method, url, body).status_code)


class TheModuleSwitch(FeesTestCase):
    def test_a_school_never_granted_fees_is_refused_with_module_disabled(self):
        ModuleSetting.objects.filter(school=self.school, module="fees").delete()
        client = self.as_user(self.admin)

        for response in (
            client.get(HEADS),
            client.post(HEADS, {"name": "Tuition"}, format="json"),
            client.get(STRUCTURES, {"academic_year_id": self.year.id}),
            client.get(PLAN, {"academic_year_id": self.year.id, "frequency": "yearly", "amount": "100"}),
        ):
            self.assertEqual(403, response.status_code)
            self.assertEqual("MODULE_DISABLED", response.data["code"])
            self.assertEqual("Fee Management is switched off for this school.", response.data["message"])

        self.assertFalse(FeeHead.objects.filter(school=self.school).exists())

    def test_a_school_that_switched_it_off_is_refused_and_granted_again_is_allowed(self):
        setting = ModuleSetting.objects.get(school=self.school, module="fees")
        setting.school_enabled = False
        setting.save()
        client = self.as_user(self.accountant)

        self.assertEqual("MODULE_DISABLED", client.get(HEADS).data["code"])

        setting.school_enabled = True
        setting.save()

        self.assertEqual(200, client.get(HEADS).status_code)
        self.assertEqual(201, client.post(HEADS, {"name": "Tuition"}, format="json").status_code)

    def test_a_record_in_a_school_with_fees_off_is_refused_by_id_too(self):
        structure_id = self.created(self.class_fee())["id"]
        ModuleSetting.objects.filter(school=self.school, module="fees").update(platform_enabled=False)

        response = self.as_user(self.root).get(f"{STRUCTURES}/{structure_id}")

        self.assertEqual(403, response.status_code)
        self.assertEqual("MODULE_DISABLED", response.data["code"])

    def test_the_module_arrives_off_and_is_in_the_matrix_for_the_office_only(self):
        from school import modules, permissions

        self.assertFalse(modules.is_enabled(factories.SchoolFactory().id, "fees"))
        self.assertEqual(
            {"SCHOOL_ADMIN": "manage", "ACCOUNTANT": "manage", "TEACHER": "none", "HOD": "none", "STAFF": "none",
             "TRANSPORT_MANAGER": "none", "DRIVER": "none", "BUS_ATTENDANT": "none"},
            {role: permissions.DEFAULTS[role]["fees"] for role in permissions.DEFAULTS},
        )
        # Settings arrive with the slices that read them: part payments with
        # F3, late fines with F4, reminders with F5.
        self.assertEqual(
            {"allow_part_payment": True, "late_fine_amount": 0, "late_fine_grace_days": 7,
             "reminder_days_before": 3, "remind_when_overdue": True},
            modules.get("fees").defaults(),
        )


class CrossSchool(FeesTestCase):
    def test_a_school_admin_cannot_touch_another_schools_fees_by_id(self):
        theirs = self.other_structure()
        client = self.as_user(self.admin)

        for response in (
            client.get(f"{STRUCTURES}/{theirs.id}"),
            client.put(f"{STRUCTURES}/{theirs.id}", {"amount": "1", "frequency": "yearly", "installments": []}, format="json"),
            client.delete(f"{STRUCTURES}/{theirs.id}"),
            client.post(f"{STRUCTURES}/{theirs.id}/publish"),
            client.patch(f"{HEADS}/{theirs.fee_head_id}", {"name": "Mine"}, format="json"),
            client.delete(f"{HEADS}/{theirs.fee_head_id}"),
        ):
            self.assertEqual(403, response.status_code, response.data)

        theirs.refresh_from_db()
        self.assertEqual(("draft", "Tuition"), (theirs.status, theirs.fee_head.name))

    def test_naming_another_school_reads_and_writes_your_own(self):
        self.head("Uniform", school=self.other)
        client = self.as_user(self.admin)

        names = {(row["school_id"], row["name"]) for row in client.get(HEADS, {"school_id": self.other.id}).data["data"]}
        self.assertEqual({(self.school.id, "Transport")}, names)

        created = self.created(client.post(HEADS, {"name": "Library", "school_id": self.other.id}, format="json"))
        self.assertEqual(self.school.id, created["school_id"])
        self.assertFalse(FeeHead.objects.filter(school=self.other, name="Library").exists())

    def test_another_schools_ids_inside_a_form_are_invalid(self):
        client = self.as_user(self.admin)
        their_head = self.head("Tuition", school=self.other)

        errors = self.errors(self.class_fee(client, academic_year_id=self.other_year.id))
        self.assertEqual(["The selected academic year id is invalid."], errors["academic_year_id"])

        errors = self.errors(self.class_fee(client, school_class_id=self.other_class.id, fee_head_id=their_head.id))
        self.assertEqual(["The selected school class id is invalid."], errors["school_class_id"])
        self.assertEqual(["The selected fee head id is invalid."], errors["fee_head_id"])

        errors = self.errors(self.route_fee(client, transport_route_id=self.other_route.id))
        self.assertEqual(["The selected transport route id is invalid."], errors["transport_route_id"])

        self.assertIn("academic_year_id", self.errors(client.get(STRUCTURES, {"academic_year_id": self.other_year.id})))
        self.assertIn("academic_year_id", self.errors(client.post(PUBLISH_ALL, {"academic_year_id": self.other_year.id}, format="json")))
        self.assertIn("academic_year_id", self.errors(client.get(PLAN, {"academic_year_id": self.other_year.id, "frequency": "yearly", "amount": "1"})))
        self.assertFalse(FeeStructure.objects.filter(school=self.school).exists())


# -- fee heads --------------------------------------------------------------------


class FeeHeads(FeesTestCase):
    def test_every_school_has_a_transport_head_made_once_and_listed_first(self):
        self.head("Tuition")
        self.head("admission")
        self.head("Exam", is_active=False)
        client = self.as_user(self.accountant)

        client.get(HEADS)
        data = client.get(HEADS).data["data"]

        self.assertEqual(1, FeeHead.objects.filter(school=self.school, is_transport=True).count())
        self.assertEqual(["Transport", "admission", "Tuition", "Exam"], [row["name"] for row in data])
        self.assertEqual(
            {"id", "school_id", "name", "is_transport", "is_active", "structures_count"}, set(data[0])
        )
        self.assertEqual((True, True, 0), (data[0]["is_transport"], data[0]["is_active"], data[0]["structures_count"]))
        self.assertFalse(data[3]["is_active"])

    def test_writing_a_fee_also_makes_the_transport_head(self):
        self.created(self.class_fee())

        self.assertTrue(FeeHead.objects.filter(school=self.school, name="Transport", is_transport=True).exists())

    def test_a_head_is_created_trimmed_and_audited(self):
        response = self.as_user(self.accountant).post(HEADS, {"name": "  Library  "}, format="json")

        head = self.created(response)
        self.assertEqual(("Library", False, True, 0, self.school.id),
                         (head["name"], head["is_transport"], head["is_active"], head["structures_count"], head["school_id"]))

        entry = AuditLog.objects.get(action="fee_head.created")
        self.assertEqual(("fees", "fee_head", head["id"], self.school.id, self.accountant.id),
                         (entry.module, entry.entity_type, entry.entity_id, entry.school_id, entry.user_id))
        self.assertEqual({"name": "Library", "is_transport": False, "is_active": True}, entry.new_values)

    def test_names_are_unique_per_school_without_regard_to_case(self):
        client = self.as_user(self.accountant)
        self.created(client.post(HEADS, {"name": "Tuition"}, format="json"))

        for name in ("tuition", "TUITION ", "transport"):
            with self.subTest(name=name):
                self.assertEqual(["The name has already been taken."],
                                 self.errors(client.post(HEADS, {"name": name}, format="json"))["name"])

        self.head("Library", school=self.other)
        self.assertEqual(201, client.post(HEADS, {"name": "library"}, format="json").status_code,
                         "another school's names are not ours")

    def test_a_name_is_required_and_at_most_100_characters(self):
        client = self.as_user(self.accountant)

        self.assertEqual(["The name field is required."], self.errors(client.post(HEADS, {}, format="json"))["name"])
        self.assertEqual(["The name field is required."], self.errors(client.post(HEADS, {"name": "   "}, format="json"))["name"])
        self.assertEqual(["The name field must not be greater than 100 characters."],
                         self.errors(client.post(HEADS, {"name": "x" * 101}, format="json"))["name"])
        self.assertEqual(201, client.post(HEADS, {"name": "x" * 100}, format="json").status_code)

    def test_a_school_has_at_most_fifty_heads_transport_included(self):
        self.transport()
        FeeHead.objects.bulk_create([FeeHead(school=self.school, name=f"Head {n}") for n in range(48)])
        client = self.as_user(self.accountant)

        self.assertEqual(201, client.post(HEADS, {"name": "The fiftieth"}, format="json").status_code)

        response = client.post(HEADS, {"name": "One too many"}, format="json")
        self.assertEqual(409, response.status_code)
        self.assertEqual("FEE_HEAD_LIMIT_REACHED", response.data["code"])
        self.assertEqual(50, FeeHead.objects.filter(school=self.school).count())

    def test_a_head_is_renamed_retired_and_brought_back(self):
        head = self.head("Tution")
        client = self.as_user(self.accountant)

        renamed = client.patch(f"{HEADS}/{head.id}", {"name": "Tuition"}, format="json")
        self.assertEqual(200, renamed.status_code, renamed.data)
        self.assertEqual("Tuition", renamed.data["name"])

        self.assertFalse(client.patch(f"{HEADS}/{head.id}", {"is_active": False}, format="json").data["is_active"])
        self.assertTrue(client.patch(f"{HEADS}/{head.id}", {"is_active": True}, format="json").data["is_active"])
        self.assertEqual(200, client.patch(f"{HEADS}/{head.id}", {"name": "TUITION"}, format="json").status_code,
                         "a head may change its own case")

        entries = AuditLog.objects.filter(action="fee_head.updated").order_by("id")
        self.assertEqual(4, entries.count())
        self.assertEqual(("Tution", "Tuition"), (entries[0].old_values["name"], entries[0].new_values["name"]))

    def test_renaming_to_a_name_in_use_is_refused(self):
        self.head("Tuition")
        library = self.head("Library")

        errors = self.errors(self.as_user(self.accountant).patch(f"{HEADS}/{library.id}", {"name": "tuition"}, format="json"))
        self.assertEqual(["The name has already been taken."], errors["name"])

        errors = self.errors(self.as_user(self.accountant).patch(f"{HEADS}/{library.id}", {"is_active": "maybe"}, format="json"))
        self.assertEqual(["The is active field must be true or false."], errors["is_active"])

    def test_the_transport_head_cannot_be_renamed_retired_or_deleted(self):
        transport = self.transport()
        client = self.as_user(self.admin)

        for response in (
            client.patch(f"{HEADS}/{transport.id}", {"name": "Bus"}, format="json"),
            client.patch(f"{HEADS}/{transport.id}", {"is_active": False}, format="json"),
            client.delete(f"{HEADS}/{transport.id}"),
        ):
            self.assertEqual(409, response.status_code)
            self.assertEqual("FEE_HEAD_PROTECTED", response.data["code"])
            self.assertEqual(
                "The Transport fee type is used for bus route fees, so it can't be renamed or retired.",
                response.data["message"],
            )

        transport.refresh_from_db()
        self.assertEqual(("Transport", True, True), (transport.name, transport.is_active, transport.is_transport))

    def test_an_unused_head_is_deleted_and_a_used_one_is_retired_instead(self):
        unused = self.head("Library")
        client = self.as_user(self.accountant)

        self.assertEqual(204, client.delete(f"{HEADS}/{unused.id}").status_code)
        self.assertFalse(FeeHead.objects.filter(pk=unused.id).exists())
        self.assertEqual({"name": "Library", "is_transport": False, "is_active": True},
                         AuditLog.objects.get(action="fee_head.deleted").old_values)

        self.created(self.class_fee())
        tuition = FeeHead.objects.get(school=self.school, name="Tuition")
        self.created(self.class_fee(school_class_id=self.class2.id, fee_head_id=tuition.id))

        response = client.delete(f"{HEADS}/{tuition.id}")
        self.assertEqual(409, response.status_code)
        self.assertEqual("FEE_HEAD_IN_USE", response.data["code"])
        self.assertEqual("This fee type is used by 2 fees. Retire it instead.", response.data["message"])
        self.assertEqual(2, client.get(HEADS).data["data"][1]["structures_count"])

    def test_a_missing_head_is_not_found(self):
        self.assertEqual(404, self.as_user(self.admin).patch(f"{HEADS}/999999", {"name": "x"}, format="json").status_code)


# -- fee structures -------------------------------------------------------------


class CreatingFees(FeesTestCase):
    def test_a_class_fee_is_created_as_a_draft_in_the_schools_currency(self):
        data = self.created(self.class_fee(currency_code="USD", school_id=self.other.id))
        tuition = FeeHead.objects.get(school=self.school, name="Tuition")

        self.assertEqual(
            {
                "school_id": self.school.id,
                "academic_year_id": self.year.id,
                "kind": "class",
                "school_class": {"id": self.class8.id, "name": "Class 8"},
                "transport_route": None,
                "fee_head": {"id": tuition.id, "name": "Tuition", "is_transport": False},
                "amount": "12000.00",
                "currency_code": "INR",
                "frequency": "yearly",
                "status": "draft",
                "published_at": None,
                # F2: a draft charges nobody.
                "students_count": 0,
            },
            {key: value for key, value in data.items() if key not in ("id", "installments", "updated_at")},
        )
        self.assertEqual(
            [(1, "First half", "2026-04-10", "6000.00"), (2, "Second half", "2026-10-10", "6000.00")],
            [(row["sequence"], row["label"], row["due_date"], row["amount"]) for row in data["installments"]],
        )
        self.assertTrue(data["updated_at"].endswith("Z"))
        self.assertEqual(self.accountant.id, FeeStructure.objects.get(pk=data["id"]).created_by_id)

        entry = AuditLog.objects.get(action="fee_structure.created")
        self.assertEqual(("fees", "fee_structure", data["id"], self.school.id),
                         (entry.module, entry.entity_type, entry.entity_id, entry.school_id))
        self.assertEqual("12000.00", entry.new_values["amount"])
        self.assertEqual(2, len(entry.new_values["installments"]))

    def test_a_route_fee_uses_the_transport_head(self):
        data = self.created(self.route_fee())

        self.assertEqual(("route", None, {"id": self.route.id, "name": "Route A"}, "Transport"),
                         (data["kind"], data["school_class"], data["transport_route"], data["fee_head"]["name"]))

    def test_every_problem_is_reported_at_once(self):
        errors = self.errors(self.as_user(self.accountant).post(STRUCTURES, {}, format="json"))

        self.assertEqual(
            {
                "academic_year_id": ["The academic year id field is required."],
                "fee_head_id": ["The fee head id field is required."],
                "amount": ["The amount field is required."],
                "frequency": ["The frequency field is required."],
                "school_class_id": ["The school class id field is required when transport route id is not present."],
            },
            errors,
        )

    def test_a_fee_is_for_a_class_or_a_route_never_both(self):
        errors = self.errors(self.class_fee(transport_route_id=self.route.id))

        self.assertEqual(["The school class id field prohibits transport route id from being present."],
                         errors["school_class_id"])

    def test_the_class_must_be_in_the_same_academic_year(self):
        next_year = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False,
                                                  start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31))
        later = factories.SchoolClassFactory(academic_year=next_year, name="Class 8", level=8)

        errors = self.errors(self.class_fee(school_class_id=later.id))

        self.assertEqual(["The selected school class id is invalid."], errors["school_class_id"])

    def test_the_transport_head_is_for_routes_and_only_routes(self):
        errors = self.errors(self.class_fee(fee_head_id=self.transport().id))
        self.assertEqual(["The Transport fee type is for bus routes. Choose a route instead of a class."],
                         errors["fee_head_id"])

        errors = self.errors(self.route_fee(fee_head_id=self.head("Tuition").id))
        self.assertEqual(["A bus route's fee uses the Transport fee type."], errors["fee_head_id"])

    def test_a_retired_head_cannot_be_used_for_a_new_fee(self):
        errors = self.errors(self.class_fee(fee_head_id=self.head("Exam", is_active=False).id))

        self.assertEqual(["The Exam fee type is retired. Bring it back before setting up fees with it."],
                         errors["fee_head_id"])

    def test_the_amount_must_be_money(self):
        cases = {
            "0": "The amount field must be at least 0.01.",
            "-5": "The amount field must be at least 0.01.",
            "10.005": "The amount field format is invalid.",
            "abc": "The amount field must be a number.",
            "10000000000.00": "The amount field must not be greater than 9,999,999,999.99.",
        }

        for amount, message in cases.items():
            with self.subTest(amount=amount):
                self.assertEqual([message], self.errors(self.class_fee(amount=amount))["amount"])

    def test_the_largest_amount_the_column_holds_is_accepted(self):
        big = "9999999999.99"
        data = self.created(self.class_fee(amount=big, installments=[{"label": "All", "due_date": "2026-04-10", "amount": big}]))

        self.assertEqual(big, data["amount"])

    def test_the_frequency_must_be_one_of_the_five(self):
        self.assertEqual(["The selected frequency is invalid."], self.errors(self.class_fee(frequency="weekly"))["frequency"])

        for frequency in ("monthly", "quarterly", "term", "yearly", "one_time"):
            FeeInstallment.objects.all().delete()
            FeeStructure.objects.all().delete()
            self.assertEqual(201, self.class_fee(frequency=frequency).status_code, frequency)

    def test_installment_problems_are_reported_under_installments_by_number(self):
        errors = self.errors(self.class_fee(installments=[
            {"label": "A", "due_date": "2026-04-10", "amount": "5000"},
            {"label": "B", "due_date": "2026-10-10", "amount": "5000"},
            {"label": "C", "due_date": "2027-05-10", "amount": "1000"},
        ]))

        self.assertEqual(
            ["Installment 3 is due on 2027-05-10, after the academic year ends (2027-03-31).",
             "The installments add up to 11,000.00 but the fee is 12,000.00."],
            errors["installments"],
        )

    def test_installments_are_required(self):
        self.assertEqual(["Add at least one installment."], self.errors(self.class_fee(installments=[]))["installments"])
        self.assertEqual(["The installments field is required."], self.errors(self.class_fee(installments=None))["installments"])

    def test_one_fee_per_head_per_class_and_per_route_each_year(self):
        self.created(self.class_fee())
        self.created(self.route_fee())

        self.assertEqual(["Class 8 already has a Tuition fee for 2026-27."], self.errors(self.class_fee())["fee_head_id"])
        self.assertEqual(["Route A already has a Transport fee for 2026-27."], self.errors(self.route_fee())["fee_head_id"])

        # Another class, another head, another year: all fine.
        self.created(self.class_fee(school_class_id=self.class2.id))
        self.created(self.class_fee(fee_head_id=self.head("Exam").id))
        next_year = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False,
                                                  start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31))
        self.created(self.route_fee(academic_year_id=next_year.id, installments=[
            {"label": "All", "due_date": "2027-04-10", "amount": "12000"},
        ]))


class ReadingFees(FeesTestCase):
    def test_a_years_fees_are_listed_classes_in_order_then_routes_each_by_head(self):
        exam = self.head("Exam")
        self.created(self.class_fee())
        self.created(self.class_fee(fee_head_id=exam.id))
        self.created(self.class_fee(school_class_id=self.class2.id))
        self.created(self.route_fee())
        other_route = factories.TransportRouteFactory(school=self.school, name="A Early Route")
        self.created(self.route_fee(transport_route_id=other_route.id))
        client = self.as_user(self.accountant)

        rows = client.get(STRUCTURES, {"academic_year_id": self.year.id}).data["data"]

        self.assertEqual(
            [("Class 2", "Tuition"), ("Class 8", "Exam"), ("Class 8", "Tuition"),
             ("A Early Route", "Transport"), ("Route A", "Transport")],
            [((row["school_class"] or row["transport_route"])["name"], row["fee_head"]["name"]) for row in rows],
        )
        self.assertEqual(3, len(client.get(STRUCTURES, {"academic_year_id": self.year.id, "kind": "class"}).data["data"]))
        self.assertEqual(2, len(client.get(STRUCTURES, {"academic_year_id": self.year.id, "kind": "route"}).data["data"]))

    def test_the_list_needs_a_year_and_a_known_kind(self):
        client = self.as_user(self.accountant)

        self.assertEqual(["The academic year id field is required."], self.errors(client.get(STRUCTURES))["academic_year_id"])
        self.assertEqual(["The selected kind is invalid."],
                         self.errors(client.get(STRUCTURES, {"academic_year_id": self.year.id, "kind": "bus"}))["kind"])

    def test_one_fee_is_read_by_id(self):
        data = self.created(self.class_fee())

        response = self.as_user(self.admin).get(f"{STRUCTURES}/{data['id']}")

        self.assertEqual(200, response.status_code)
        self.assertEqual(data, response.data)
        self.assertEqual(404, self.as_user(self.admin).get(f"{STRUCTURES}/999999").status_code)


class ChangingFees(FeesTestCase):
    def test_put_replaces_the_amount_frequency_and_every_installment(self):
        data = self.created(self.class_fee())
        old_ids = [row["id"] for row in data["installments"]]

        response = self.as_user(self.accountant).put(f"{STRUCTURES}/{data['id']}", {
            "amount": "9000.00",
            "frequency": "quarterly",
            "installments": [
                {"label": "Q1", "due_date": "2026-04-10", "amount": "3000"},
                {"label": "Q2", "due_date": "2026-07-10", "amount": "3000"},
                {"label": "Q3", "due_date": "2026-10-10", "amount": "3000"},
            ],
            # The identity of a fee is not this form's to change.
            "school_class_id": self.class2.id, "fee_head_id": self.transport().id, "academic_year_id": 1,
        }, format="json")

        self.assertEqual(200, response.status_code, response.data)
        updated = response.data
        self.assertEqual(("9000.00", "quarterly", "Class 8", "Tuition"),
                         (updated["amount"], updated["frequency"], updated["school_class"]["name"], updated["fee_head"]["name"]))
        self.assertEqual([(1, "Q1"), (2, "Q2"), (3, "Q3")], [(row["sequence"], row["label"]) for row in updated["installments"]])
        self.assertFalse(FeeInstallment.objects.filter(pk__in=old_ids).exists())

        entry = AuditLog.objects.get(action="fee_structure.updated")
        self.assertEqual(("12000.00", "9000.00"), (entry.old_values["amount"], entry.new_values["amount"]))
        self.assertEqual(3, len(entry.new_values["installments"]))

    def test_put_is_validated_like_a_new_fee(self):
        data = self.created(self.class_fee())

        errors = self.errors(self.as_user(self.accountant).put(f"{STRUCTURES}/{data['id']}", {
            "amount": "100", "frequency": "fortnightly",
            "installments": [{"label": "A", "due_date": "2026-03-01", "amount": "100"}],
        }, format="json"))

        self.assertEqual(["The selected frequency is invalid."], errors["frequency"])
        self.assertEqual(["Installment 1 is due on 2026-03-01, before the academic year starts (2026-04-01)."],
                         errors["installments"])
        self.assertEqual(2, FeeInstallment.objects.filter(fee_structure_id=data["id"]).count(), "nothing changed")

    def test_a_published_fee_can_still_be_edited_in_f1(self):
        data = self.created(self.class_fee())
        client = self.as_user(self.accountant)
        client.post(f"{STRUCTURES}/{data['id']}/publish")

        response = client.put(f"{STRUCTURES}/{data['id']}", {
            "amount": "12000", "frequency": "yearly", "installments": two_installments("4000", "8000"),
        }, format="json")

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual("published", response.data["status"])

    def test_only_a_draft_is_deleted_and_its_installments_go_with_it(self):
        draft = self.created(self.class_fee())
        published = self.created(self.route_fee())
        client = self.as_user(self.accountant)
        client.post(f"{STRUCTURES}/{published['id']}/publish")

        self.assertEqual(204, client.delete(f"{STRUCTURES}/{draft['id']}").status_code)
        self.assertFalse(FeeStructure.objects.filter(pk=draft["id"]).exists())
        self.assertFalse(FeeInstallment.objects.filter(fee_structure_id=draft["id"]).exists())
        self.assertEqual(draft["id"], AuditLog.objects.get(action="fee_structure.deleted").entity_id)

        response = client.delete(f"{STRUCTURES}/{published['id']}")
        self.assertEqual(409, response.status_code)
        self.assertEqual(("FEE_STRUCTURE_PUBLISHED", "A published fee can't be deleted."),
                         (response.data["code"], response.data["message"]))
        self.assertTrue(FeeStructure.objects.filter(pk=published["id"]).exists())


class Publishing(FeesTestCase):
    def test_publishing_is_one_way_and_publishing_again_changes_nothing(self):
        data = self.created(self.class_fee())
        client = self.as_user(self.admin)

        first = client.post(f"{STRUCTURES}/{data['id']}/publish")
        self.assertEqual(200, first.status_code)
        self.assertEqual("published", first.data["status"])
        self.assertIsNotNone(first.data["published_at"])
        self.assertEqual(self.admin.id, FeeStructure.objects.get(pk=data["id"]).published_by_id)

        again = client.post(f"{STRUCTURES}/{data['id']}/publish")
        self.assertEqual(200, again.status_code)
        self.assertEqual(first.data["published_at"], again.data["published_at"])

        entries = AuditLog.objects.filter(action="fee_structure.published")
        self.assertEqual(1, entries.count())
        self.assertEqual(({"status": "draft", "published_at": None}, "published"),
                         (entries[0].old_values, entries[0].new_values["status"]))

    def test_publishing_a_year_publishes_every_draft_of_it_and_nothing_else(self):
        one = self.created(self.class_fee())
        two = self.created(self.route_fee())
        already = self.created(self.class_fee(school_class_id=self.class2.id))
        client = self.as_user(self.accountant)
        client.post(f"{STRUCTURES}/{already['id']}/publish")
        next_year = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False,
                                                  start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31))
        later = self.created(self.route_fee(academic_year_id=next_year.id, installments=[
            {"label": "All", "due_date": "2027-04-10", "amount": "12000"},
        ]))
        theirs = self.other_structure()

        response = client.post(PUBLISH_ALL, {"academic_year_id": self.year.id}, format="json")

        self.assertEqual(200, response.status_code)
        # F2 added what publishing charged; nobody is enrolled here.
        self.assertEqual({"published": 2, "students": 0, "dues_created": 0}, response.data)
        self.assertEqual(
            {one["id"]: "published", two["id"]: "published", already["id"]: "published", later["id"]: "draft",
             theirs.id: "draft"},
            dict(FeeStructure.objects.values_list("id", "status")),
        )
        self.assertEqual(3, AuditLog.objects.filter(action="fee_structure.published").count())
        self.assertEqual({"published": 0, "students": 0, "dues_created": 0},
                         client.post(PUBLISH_ALL, {"academic_year_id": self.year.id}, format="json").data)

    def test_publishing_a_year_needs_one(self):
        errors = self.errors(self.as_user(self.accountant).post(PUBLISH_ALL, {}, format="json"))

        self.assertEqual(["The academic year id field is required."], errors["academic_year_id"])


# -- the installment-plan helper ------------------------------------------------


class InstallmentPlans(FeesTestCase):
    def plan(self, year=None, **params):
        query = {"academic_year_id": (year or self.year).id, "amount": "12000", **params}

        return self.as_user(self.accountant).get(PLAN, query)

    def test_monthly_offers_one_installment_per_month_on_the_tenth_by_default(self):
        response = self.plan(frequency="monthly")

        self.assertEqual(200, response.status_code, response.data)
        rows = response.data["installments"]
        self.assertEqual(12, len(rows))
        self.assertEqual({"label": "April 2026", "due_date": "2026-04-10", "amount": "1000.00"}, rows[0])
        self.assertEqual({"label": "March 2027", "due_date": "2027-03-10", "amount": "1000.00"}, rows[-1])
        self.assertFalse(FeeStructure.objects.exists(), "nothing is saved")

    def test_a_late_due_day_is_the_last_day_of_a_short_month_even_in_a_leap_year(self):
        rows = self.plan(frequency="monthly", due_day=31).data["installments"]
        self.assertEqual("2027-02-28", next(row for row in rows if row["label"] == "February 2027")["due_date"])

        leap = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False,
                                             start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31))
        rows = self.plan(year=leap, frequency="monthly", due_day=31).data["installments"]
        self.assertEqual("2028-02-29", next(row for row in rows if row["label"] == "February 2028")["due_date"])

    def test_the_remainder_cents_go_on_the_last_installment(self):
        rows = self.plan(frequency="monthly", amount="1000").data["installments"]

        self.assertEqual(["83.33"] * 11 + ["83.37"], [row["amount"] for row in rows])

    def test_quarterly_is_four_quarters(self):
        rows = self.plan(frequency="quarterly", due_day=5).data["installments"]

        self.assertEqual(
            [("Quarter 1", "2026-04-05"), ("Quarter 2", "2026-07-05"), ("Quarter 3", "2026-10-05"), ("Quarter 4", "2027-01-05")],
            [(row["label"], row["due_date"]) for row in rows],
        )

    def test_per_term_follows_the_years_terms_in_order(self):
        factories.AcademicTermFactory(academic_year=self.year, name="Term 2", sequence_number=2,
                                      start_date=dt.date(2026, 9, 1), end_date=dt.date(2026, 12, 31))
        factories.AcademicTermFactory(academic_year=self.year, name="Term 1", sequence_number=1,
                                      start_date=dt.date(2026, 4, 1), end_date=dt.date(2026, 8, 31))

        rows = self.plan(frequency="term", amount="100").data["installments"]

        self.assertEqual(
            [{"label": "Term 1", "due_date": "2026-04-01", "amount": "50.00"},
             {"label": "Term 2", "due_date": "2026-09-01", "amount": "50.00"}],
            rows,
        )

    def test_per_term_in_a_year_without_terms_is_refused(self):
        errors = self.errors(self.plan(frequency="term"))

        self.assertEqual(
            ["This academic year has no terms yet. Add them under Academic Years, or choose another frequency."],
            errors["frequency"],
        )

    def test_yearly_and_one_time_fall_due_on_the_first_day_of_the_year(self):
        self.assertEqual([{"label": "Annual", "due_date": "2026-04-01", "amount": "12000.00"}],
                         self.plan(frequency="yearly", due_day=20).data["installments"])
        self.assertEqual([{"label": "One-time", "due_date": "2026-04-01", "amount": "12000.00"}],
                         self.plan(frequency="one_time").data["installments"])

    def test_what_the_plan_needs(self):
        errors = self.errors(self.as_user(self.accountant).get(PLAN))
        self.assertEqual({"academic_year_id", "frequency", "amount"}, set(errors))

        errors = self.errors(self.plan(frequency="weekly", amount="0", due_day=32))
        self.assertEqual(["The selected frequency is invalid."], errors["frequency"])
        self.assertEqual(["The amount field must be at least 0.01."], errors["amount"])
        self.assertEqual(["The due day field must be between 1 and 31."], errors["due_day"])

        self.assertEqual(["The due day field must be between 1 and 31."],
                         self.errors(self.plan(frequency="monthly", due_day=0))["due_day"])
        self.assertEqual(["The amount is too small to split into 12 installments."],
                         self.errors(self.plan(frequency="monthly", amount="0.11"))["amount"])
        self.assertEqual(200, self.plan(frequency="monthly", amount="0.12").status_code)


# -- what fees are built on ------------------------------------------------------


class DeletingWhatFeesPointAt(FeesTestCase):
    def assert_refused(self, response, message):
        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual(("HAS_DEPENDENT_RECORDS", message), (response.data["code"], response.data["message"]))

    def test_a_class_with_fees_is_not_deleted(self):
        self.created(self.class_fee(school_class_id=self.class2.id))

        self.assert_refused(self.as_user(self.admin).delete(f"/api/v1/classes/{self.class2.id}"),
                            "This class has fees set up for it. Delete its fees first.")

        FeeInstallment.objects.all().delete()
        FeeStructure.objects.all().delete()
        self.assertEqual(204, self.as_user(self.admin).delete(f"/api/v1/classes/{self.class2.id}").status_code)

    def test_a_route_with_a_bus_fee_is_not_deleted(self):
        self.created(self.route_fee())

        self.assert_refused(self.as_user(self.admin).delete(f"/api/v1/transport/routes/{self.route.id}"),
                            "This route has a bus fee set up for it. Delete its fees first.")

    def test_a_year_with_only_route_fees_is_not_deleted(self):
        year = factories.AcademicYearFactory(school=self.school, name="2027-28", is_current=False,
                                             start_date=dt.date(2027, 4, 1), end_date=dt.date(2028, 3, 31))
        self.created(self.route_fee(academic_year_id=year.id, installments=[
            {"label": "All", "due_date": "2027-04-10", "amount": "12000"},
        ]))

        self.assert_refused(self.as_user(self.admin).delete(f"/api/v1/academic-years/{year.id}"),
                            "This academic year has fees set up for it. Delete its fees first.")

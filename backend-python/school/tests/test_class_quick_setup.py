"""Classes in one step (docs/onboarding.md, slice O1).

A school should not have to know that a class has a "level": "LKG" and
"Class 7" say which year they are. And Nursery to Class 10, each with its
sections, is one tick-list rather than eleven forms.
"""

from django.core.cache import cache
from django.test import SimpleTestCase, TestCase
from rest_framework.test import APIClient

from school import class_levels, factories, tokens
from school.enums import UserRole
from school.models import AuditLog, ClassSection, SchoolClass


class Inference(SimpleTestCase):
    def test_pre_primary_names_order_before_class_one(self):
        self.assertEqual(-3, class_levels.infer("Playgroup"))
        self.assertEqual(-2, class_levels.infer("Nursery"))
        self.assertEqual(-1, class_levels.infer("LKG"))
        self.assertEqual(-1, class_levels.infer("KG 1"))
        self.assertEqual(0, class_levels.infer("UKG"))
        self.assertEqual(0, class_levels.infer("Upper K.G."))

    def test_numbered_names_in_the_ways_schools_write_them(self):
        for name in ("Class 7", "Grade 7", "Std. VII", "Standard 7", "7th", "7", "class vii"):
            self.assertEqual(7, class_levels.infer(name), name)

    def test_a_name_that_says_nothing_gives_nothing(self):
        for name in ("Rose", "Class 13", "Class 0", "", None, "Senior Batch"):
            self.assertIsNone(class_levels.infer(name), name)

    def test_the_standard_list_is_in_order_and_nursery_to_ten_is_ticked(self):
        levels = [level for _, level in class_levels.STANDARD]
        self.assertEqual(sorted(levels), levels)
        self.assertEqual("Nursery", class_levels.DEFAULT_SELECTION[0])
        self.assertEqual("Class 10", class_levels.DEFAULT_SELECTION[-1])
        self.assertEqual(13, len(class_levels.DEFAULT_SELECTION))


class SetupTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.year = factories.AcademicYearFactory(school=self.school)
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client


class LevelFromTheName(SetupTest):
    def create(self, **body):
        return self.client.post("/api/v1/classes", {"academic_year_id": self.year.id, **body}, format="json")

    def test_a_class_without_a_level_takes_it_from_its_name(self):
        response = self.create(name="LKG")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(-1, SchoolClass.objects.get(pk=response.data["id"]).level)

    def test_a_level_given_wins_over_the_name(self):
        response = self.create(name="Class 7", level=6)

        self.assertEqual(6, SchoolClass.objects.get(pk=response.data["id"]).level)

    def test_a_name_that_says_nothing_asks_for_the_level(self):
        response = self.create(name="Rose")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("Choose which year", response.data["details"]["errors"]["level"][0])

    def test_pre_primary_levels_down_to_playgroup_are_allowed(self):
        self.assertEqual(201, self.create(name="Tiny Tots", level=-3).status_code)
        self.assertEqual(422, self.create(name="Babies", level=-4).status_code)

    def test_classes_list_nursery_lkg_ukg_then_class_one(self):
        for name in ("Class 1", "UKG", "Nursery", "Class 10", "LKG", "Class 2"):
            self.create(name=name)

        response = self.client.get(f"/api/v1/classes?academic_year_id={self.year.id}")

        self.assertEqual(
            ["Nursery", "LKG", "UKG", "Class 1", "Class 2", "Class 10"],
            [row["name"] for row in response.data["data"]],
        )


class QuickSetup(SetupTest):
    url = "/api/v1/classes/quick-setup"

    def post(self, client=None, **overrides):
        body = {"academic_year_id": self.year.id, "classes": ["Nursery", "LKG", "Class 1"], "sections": 2}
        body.update(overrides)

        return (client or self.client).post(self.url, body, format="json")

    def test_it_offers_the_standard_classes_with_nursery_to_ten_ticked(self):
        response = self.client.get(self.url)

        self.assertEqual(200, response.status_code, response.data)
        rows = response.data["classes"]
        self.assertEqual("Playgroup", rows[0]["name"])
        self.assertFalse(rows[0]["selected"])
        self.assertTrue(next(r for r in rows if r["name"] == "Class 10")["selected"])
        self.assertFalse(next(r for r in rows if r["name"] == "Class 11")["selected"])

    def test_the_ticked_classes_are_created_with_their_sections(self):
        response = self.post()

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(["Nursery", "LKG", "Class 1"], response.data["created"])
        classes = SchoolClass.objects.filter(academic_year=self.year).order_by("level")
        self.assertEqual([("Nursery", -2), ("LKG", -1), ("Class 1", 1)], [(c.name, c.level) for c in classes])
        for school_class in classes:
            self.assertEqual(self.school.id, school_class.school_id)
            sections = ClassSection.objects.filter(school_class=school_class).order_by("name")
            self.assertEqual(["A", "B"], list(sections.values_list("name", flat=True)))

    def test_classes_come_out_in_class_order_whatever_order_they_were_ticked_in(self):
        response = self.post(classes=["Class 1", "Nursery", "LKG"])

        self.assertEqual(["Nursery", "LKG", "Class 1"], response.data["created"])

    def test_a_class_the_year_already_has_is_left_alone(self):
        existing = factories.SchoolClassFactory(school=self.school, academic_year=self.year, name="LKG", level=-1)

        response = self.post()

        self.assertEqual(["Nursery", "Class 1"], response.data["created"])
        self.assertEqual(["LKG"], response.data["skipped"])
        self.assertFalse(ClassSection.objects.filter(school_class=existing).exists())

    def test_running_it_twice_adds_nothing_twice(self):
        self.post()
        again = self.post()

        self.assertEqual([], again.data["created"])
        self.assertEqual(3, SchoolClass.objects.filter(academic_year=self.year).count())
        self.assertEqual(6, ClassSection.objects.filter(school_class__academic_year=self.year).count())

    def test_what_it_creates_is_audited(self):
        before = AuditLog.objects.count()

        self.post(classes=["Nursery"], sections=1)

        self.assertEqual(before + 2, AuditLog.objects.count())

    def test_a_name_that_is_not_standard_is_refused(self):
        response = self.post(classes=["Nursery", "Rose"])

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("Rose", response.data["details"]["errors"]["classes"][0])
        self.assertFalse(SchoolClass.objects.exists())

    def test_nothing_ticked_is_refused(self):
        response = self.post(classes=[])

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("classes", response.data["details"]["errors"])

    def test_sections_must_be_between_one_and_six(self):
        self.assertEqual(422, self.post(sections=0).status_code)
        self.assertEqual(422, self.post(sections=7).status_code)
        self.assertEqual(201, self.post(sections=6).status_code)

    def test_another_schools_year_is_refused(self):
        elsewhere = factories.AcademicYearFactory(school=factories.SchoolFactory())

        response = self.post(academic_year_id=elsewhere.id)

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("academic_year_id", response.data["details"]["errors"])
        self.assertFalse(SchoolClass.objects.exists())

    def test_the_school_id_sent_by_the_client_is_not_trusted(self):
        other = factories.SchoolFactory()

        self.post(school_id=other.id)

        self.assertFalse(SchoolClass.objects.filter(school_id=other.id).exists())

    def test_a_teacher_may_not(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, self.post(client=teacher).status_code)
        self.assertEqual(403, teacher.get(self.url).status_code)
        self.assertFalse(SchoolClass.objects.exists())

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get(self.url).status_code)

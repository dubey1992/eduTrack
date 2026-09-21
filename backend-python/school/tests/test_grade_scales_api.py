"""Grade scales, over HTTP (docs/assessments.md).

The bands are the risk. A set with a gap in it gives some mark no grade at
all; a set that overlaps gives one mark two grades. Both are refused here,
and both are the kind of thing nobody notices until results are published,
so the boundaries get their own tests.

The rule a reader should hold on to: **a percentage falls in the highest
band whose minimum it reaches.** That is what lets a school write 91-100 and
81-90, the way it says them out loud, and still have a grade for 90.5.
"""

from decimal import Decimal

from django.core.cache import cache
from django.test import TestCase
from rest_framework.test import APIClient

from school import factories, tokens
from school.enums import UserRole
from school.models import GradeBand, GradeScale
from school.services import GradeScaleService

URL = "/api/v1/grade-scales"


def band(label: str, low, high, failing: bool = False) -> dict:
    return {"label": label, "min_percentage": low, "max_percentage": high, "is_failing": failing}


# A two-band pass/fail scale, the smallest set that is actually usable.
PASS_FAIL = [band("Pass", 33, 100), band("Fail", 0, 32, failing=True)]


class GradeScaleApiTest(TestCase):
    def setUp(self):
        cache.clear()
        self.school = factories.SchoolFactory()
        self.admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        self.client = self.as_user(self.admin)

    def as_user(self, user) -> APIClient:
        client = APIClient()
        client.credentials(HTTP_AUTHORIZATION="Bearer " + tokens.issue(user))

        return client

    def payload(self, **overrides) -> dict:
        body = {"school_id": self.school.id, "name": "Secondary", "bands": PASS_FAIL}
        body.update(overrides)

        return body

    def errors(self, response) -> dict:
        return response.data["details"]["errors"]

    def make_scale(self, **overrides) -> GradeScale:
        fields = {"school": self.school, "name": "Secondary", "is_default": True}
        fields.update(overrides)
        scale = factories.GradeScaleFactory(**fields)
        factories.GradeBandFactory(grade_scale=scale, label="Fail", min_percentage=0, max_percentage=32, is_failing=True)
        factories.GradeBandFactory(grade_scale=scale, label="Pass", min_percentage=33, max_percentage=100)

        return scale


class CreatingAScale(GradeScaleApiTest):
    def test_a_scale_is_created_with_its_bands_highest_first(self):
        response = self.client.post(URL, self.payload(), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual("Secondary", response.data["name"])
        self.assertEqual(["Pass", "Fail"], [row["label"] for row in response.data["bands"]])
        self.assertEqual("33.00", response.data["bands"][0]["min_percentage"])
        self.assertIs(True, response.data["bands"][1]["is_failing"])

    def test_the_first_scale_of_a_school_is_its_default_whatever_was_asked(self):
        response = self.client.post(URL, self.payload(is_default=False), format="json")

        self.assertIs(True, response.data["is_default"])

    def test_a_later_scale_is_only_the_default_when_it_says_so(self):
        self.make_scale()

        response = self.client.post(URL, self.payload(name="Primary"), format="json")

        self.assertIs(False, response.data["is_default"])

    def test_making_one_default_clears_the_other(self):
        first = self.make_scale()

        self.client.post(URL, self.payload(name="Primary", is_default=True), format="json")

        first.refresh_from_db()
        self.assertIs(False, first.is_default)
        self.assertEqual(1, GradeScale.objects.filter(school=self.school, is_default=True).count())

    def test_another_schools_default_is_left_alone(self):
        elsewhere = factories.GradeScaleFactory(is_default=True)

        self.client.post(URL, self.payload(is_default=True), format="json")

        elsewhere.refresh_from_db()
        self.assertIs(True, elsewhere.is_default)

    def test_two_scales_of_one_school_cannot_share_a_name(self):
        self.make_scale(name="Secondary")

        response = self.client.post(URL, self.payload(name="Secondary"), format="json")

        self.assertEqual(422, response.status_code, response.data)

    def test_a_teacher_may_not_create_one(self):
        teacher = self.as_user(factories.UserFactory(school=self.school, role=UserRole.TEACHER))

        self.assertEqual(403, teacher.post(URL, self.payload(), format="json").status_code)


class TheBandsMustCoverEveryMark(GradeScaleApiTest):
    def test_a_scale_needs_at_least_one_band(self):
        response = self.client.post(URL, self.payload(bands=[]), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("A scale needs at least one band.", self.errors(response)["bands"][0])

    def test_one_band_covering_everything_is_allowed(self):
        response = self.client.post(URL, self.payload(bands=[band("Recorded", 0, 100)]), format="json")

        self.assertEqual(201, response.status_code, response.data)

    def test_the_lowest_band_must_start_at_zero(self):
        response = self.client.post(
            URL, self.payload(bands=[band("Pass", 33, 100), band("Fail", 1, 32)]), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The lowest band must start at 0, so every mark has a grade.",
            self.errors(response)["bands.1.min_percentage"][0],
        )

    def test_the_highest_band_must_end_at_one_hundred(self):
        response = self.client.post(
            URL, self.payload(bands=[band("Pass", 33, 99), band("Fail", 0, 32)]), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The highest band must end at 100, so full marks have a grade.",
            self.errors(response)["bands.0.max_percentage"][0],
        )

    def test_overlapping_bands_are_refused_and_name_the_one_in_the_way(self):
        response = self.client.post(
            URL, self.payload(bands=[band("Pass", 32, 100), band("Fail", 0, 32)]), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            'This band overlaps "Fail", which runs to 32.00.',
            self.errors(response)["bands.0.min_percentage"][0],
        )

    def test_bands_that_leave_a_gap_are_allowed_and_the_gap_reads_downwards(self):
        # 91-100 and 81-90 is how a school says it. 90.5 is nobody's A1, and
        # the service resolves it to the band below rather than to nothing.
        response = self.client.post(
            URL,
            self.payload(bands=[band("A1", 91, 100), band("A2", 81, 90), band("Rest", 0, 80)]),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)

        scale = GradeScale.objects.prefetch_related("bands").get(pk=response.data["id"])
        self.assertEqual("A2", GradeScaleService.grade_for(scale, Decimal("90.50")).label)
        self.assertEqual("A1", GradeScaleService.grade_for(scale, Decimal("91.00")).label)
        self.assertEqual("A1", GradeScaleService.grade_for(scale, Decimal("100.00")).label)
        self.assertEqual("Rest", GradeScaleService.grade_for(scale, Decimal("0.00")).label)
        self.assertIsNone(GradeScaleService.grade_for(scale, None))

    def test_a_band_may_cover_a_single_percentage(self):
        response = self.client.post(
            URL,
            self.payload(bands=[band("Perfect", 100, 100), band("Rest", 0, 99)]),
            format="json",
        )

        self.assertEqual(201, response.status_code, response.data)

    def test_a_percentage_outside_zero_to_a_hundred_is_refused(self):
        # The message matters, not just the field: "must end at 100" would
        # also land here, and it would be the wrong thing to tell somebody
        # who typed 101.
        for value in (-1, 101, "200"):
            with self.subTest(value=value):
                response = self.client.post(
                    URL, self.payload(bands=[band("Odd", 0, value)]), format="json"
                )

                self.assertEqual(422, response.status_code, response.data)
                self.assertEqual(
                    "The max percentage field must be between 0 and 100.",
                    self.errors(response)["bands.0.max_percentage"][0],
                )

    def test_a_percentage_that_is_not_a_number_is_refused(self):
        response = self.client.post(URL, self.payload(bands=[band("Odd", "ninety", 100)]), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            "The min percentage field must be a number.", self.errors(response)["bands.0.min_percentage"][0]
        )

    def test_a_missing_percentage_is_refused(self):
        response = self.client.post(
            URL, self.payload(bands=[{"label": "Odd", "max_percentage": 100}]), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("bands.0.min_percentage", self.errors(response))

    def test_a_band_that_ends_before_it_starts_is_refused(self):
        response = self.client.post(URL, self.payload(bands=[band("Odd", 50, 10)]), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("bands.0.max_percentage", self.errors(response))

    def test_two_bands_cannot_share_a_label(self):
        response = self.client.post(
            URL, self.payload(bands=[band("A", 51, 100), band("A", 0, 50)]), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual('"A" appears twice.', self.errors(response)["bands.1.label"][0])

    def test_a_band_needs_a_label(self):
        response = self.client.post(URL, self.payload(bands=[band("", 0, 100)]), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertIn("bands.0.label", self.errors(response))

    def test_every_broken_band_is_reported_at_once(self):
        response = self.client.post(
            URL, self.payload(name="", bands=[band("", 0, 100), band("B", "x", 50)]), format="json"
        )

        self.assertEqual(422, response.status_code, response.data)
        for field in ("name", "bands.0.label", "bands.1.min_percentage"):
            self.assertIn(field, self.errors(response))

    def test_a_scale_cannot_carry_an_absurd_number_of_bands(self):
        many = [band(f"B{index}", index, index) for index in range(0, 25)]

        response = self.client.post(URL, self.payload(bands=many), format="json")

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual("A scale can have at most 20 bands.", self.errors(response)["bands"][0])

    def test_bands_are_not_a_list(self):
        response = self.client.post(URL, self.payload(bands="A1"), format="json")

        self.assertEqual(422, response.status_code, response.data)


class EditingAScale(GradeScaleApiTest):
    def setUp(self):
        super().setUp()
        self.scale = self.make_scale()

    def test_the_bands_are_replaced_as_a_set(self):
        response = self.client.put(
            f"{URL}/{self.scale.id}",
            {"name": "Secondary", "bands": [band("A", 61, 100), band("B", 33, 60), band("C", 0, 32, failing=True)]},
            format="json",
        )

        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(["A", "B", "C"], [row["label"] for row in response.data["bands"]])
        self.assertEqual(3, GradeBand.objects.filter(grade_scale=self.scale).count())

    def test_a_refused_edit_leaves_the_old_bands_alone(self):
        response = self.client.put(
            f"{URL}/{self.scale.id}",
            {"name": "Secondary", "bands": [band("A", 61, 100), band("B", 33, 70)]},
            format="json",
        )

        self.assertEqual(422, response.status_code, response.data)
        self.assertEqual(
            {"Fail", "Pass"}, set(GradeBand.objects.filter(grade_scale=self.scale).values_list("label", flat=True))
        )

    def test_a_scale_can_be_made_the_default(self):
        other = self.make_scale(name="Primary", is_default=False)

        response = self.client.put(
            f"{URL}/{other.id}", {"name": "Primary", "is_default": True, "bands": PASS_FAIL}, format="json"
        )

        self.scale.refresh_from_db()
        self.assertEqual(200, response.status_code, response.data)
        self.assertIs(True, response.data["is_default"])
        self.assertIs(False, self.scale.is_default)

    def test_an_edit_cannot_quietly_remove_the_only_default(self):
        response = self.client.put(
            f"{URL}/{self.scale.id}", {"name": "Secondary", "is_default": False, "bands": PASS_FAIL}, format="json"
        )

        self.scale.refresh_from_db()
        self.assertEqual(200, response.status_code, response.data)
        self.assertIs(True, self.scale.is_default, "is_default: false never demotes, it only ever promotes")

    def test_a_scale_cannot_be_moved_to_another_school(self):
        elsewhere = factories.SchoolFactory()

        response = self.client.put(
            f"{URL}/{self.scale.id}",
            {"school_id": elsewhere.id, "name": "Secondary", "bands": PASS_FAIL},
            format="json",
        )

        self.scale.refresh_from_db()
        self.assertEqual(200, response.status_code, response.data)
        self.assertEqual(self.school.id, self.scale.school_id)


class DeletingAScale(GradeScaleApiTest):
    def test_the_only_scale_can_be_deleted(self):
        scale = self.make_scale()

        response = self.client.delete(f"{URL}/{scale.id}")

        self.assertEqual(204, response.status_code)
        self.assertFalse(GradeScale.objects.filter(pk=scale.id).exists())
        self.assertFalse(GradeBand.objects.filter(grade_scale_id=scale.id).exists(), "the bands go with it")

    def test_the_default_cannot_be_deleted_while_another_remains(self):
        default = self.make_scale()
        self.make_scale(name="Primary", is_default=False)

        response = self.client.delete(f"{URL}/{default.id}")

        self.assertEqual(409, response.status_code, response.data)
        self.assertEqual(
            "This is the school's default grade scale. Make another one the default first.",
            response.data["message"],
        )

    def test_a_scale_that_is_not_the_default_can_be_deleted(self):
        self.make_scale()
        spare = self.make_scale(name="Primary", is_default=False)

        self.assertEqual(204, self.client.delete(f"{URL}/{spare.id}").status_code)


class WhoMayDoWhat(GradeScaleApiTest):
    def setUp(self):
        super().setUp()
        self.scale = self.make_scale()

    def test_every_role_of_the_school_may_read_them(self):
        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.ACCOUNTANT):
            with self.subTest(role=role):
                reader = self.as_user(factories.UserFactory(school=self.school, role=role))

                response = reader.get(URL)

                self.assertEqual(200, response.status_code, response.data)
                self.assertEqual([self.scale.id], [row["id"] for row in response.data["data"]])

    def test_nobody_but_an_administrator_may_change_them(self):
        for role in (UserRole.HOD, UserRole.TEACHER, UserRole.STAFF, UserRole.ACCOUNTANT):
            with self.subTest(role=role):
                writer = self.as_user(factories.UserFactory(school=self.school, role=role))

                self.assertEqual(403, writer.post(URL, self.payload(name="Nope"), format="json").status_code)
                self.assertEqual(
                    403,
                    writer.put(f"{URL}/{self.scale.id}", {"name": "Nope", "bands": PASS_FAIL}, format="json").status_code,
                )
                self.assertEqual(403, writer.delete(f"{URL}/{self.scale.id}").status_code)

    def test_a_signed_out_caller_gets_401(self):
        self.assertEqual(401, APIClient().get(URL).status_code)


class SchoolIsolation(GradeScaleApiTest):
    def setUp(self):
        super().setUp()
        self.mine = self.make_scale()
        self.elsewhere = factories.SchoolFactory()
        self.theirs = factories.GradeScaleFactory(school=self.elsewhere, name="Theirs")
        factories.GradeBandFactory(grade_scale=self.theirs)

    def test_the_list_never_includes_another_schools_scales(self):
        response = self.client.get(URL)

        self.assertEqual([self.mine.id], [row["id"] for row in response.data["data"]])

    def test_a_school_id_in_the_query_string_does_not_widen_the_list(self):
        response = self.client.get(URL, {"school_id": self.elsewhere.id})

        self.assertNotIn(self.theirs.id, [row["id"] for row in response.data["data"]])

    def test_another_schools_scale_cannot_be_read_edited_or_deleted(self):
        self.assertEqual(403, self.client.get(f"{URL}/{self.theirs.id}").status_code)
        self.assertEqual(
            403,
            self.client.put(f"{URL}/{self.theirs.id}", {"name": "Mine", "bands": PASS_FAIL}, format="json").status_code,
        )
        self.assertEqual(403, self.client.delete(f"{URL}/{self.theirs.id}").status_code)

    def test_a_new_scale_lands_in_the_actors_school_whatever_was_asked_for(self):
        response = self.client.post(URL, self.payload(school_id=self.elsewhere.id, name="Sneaky"), format="json")

        self.assertEqual(201, response.status_code, response.data)
        self.assertEqual(self.school.id, response.data["school_id"])

    def test_a_group_admin_reaches_a_branchs_scales(self):
        branch = factories.SchoolFactory(parent_school=self.school)
        branch_scale = factories.GradeScaleFactory(school=branch, name="Branch")
        factories.GradeBandFactory(grade_scale=branch_scale)
        group_admin = self.as_user(factories.UserFactory(school=self.school, role=UserRole.GROUP_ADMIN))

        response = group_admin.get(URL, {"school_id": branch.id})

        self.assertEqual([branch_scale.id], [row["id"] for row in response.data["data"]])

    def test_a_super_admin_reads_any_schools_scales(self):
        root = self.as_user(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        response = root.get(URL, {"school_id": self.elsewhere.id})

        self.assertEqual([self.theirs.id], [row["id"] for row in response.data["data"]])


class TheListReadsInOrder(GradeScaleApiTest):
    def test_the_default_comes_first_then_by_name(self):
        self.make_scale(name="Zebra", is_default=True)
        self.make_scale(name="Alpha", is_default=False)
        self.make_scale(name="Middle", is_default=False)

        response = self.client.get(URL)

        self.assertEqual(["Zebra", "Alpha", "Middle"], [row["name"] for row in response.data["data"]])

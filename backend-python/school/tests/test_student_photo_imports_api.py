"""Student photos in bulk, by admission number (docs/student-photos.md,
P2): matching file names to students, the preview, the batches, who may,
and that nothing crosses from one school to another.
"""

from django.core.files.uploadedfile import SimpleUploadedFile
from django.test import SimpleTestCase
from rest_framework.test import APIClient

from school import factories, student_photos
from school.enums import StudentStatus
from school.models import AuditLog, Student

from . import test_student_photos_api as single
from .test_profile_api import image_bytes

PREVIEW = "/api/v1/imports/student-photos/preview"
STORE = "/api/v1/imports/student-photos"


def photo_file(name: str, data: bytes | None = None, content_type: str = "image/jpeg"):
    return SimpleUploadedFile(name, image_bytes(fmt="JPEG") if data is None else data, content_type=content_type)


class Matching(SimpleTestCase):
    def test_slash_dash_and_underscore_are_the_same_and_capitals_do_not_matter(self):
        key = student_photos.match_key("SPHS/26/01A01")

        for name in ("SPHS-26-01A01", "sphs_26_01a01", " Sphs-26_01A01 "):
            self.assertEqual(key, student_photos.match_key(name), name)

    def test_the_name_is_cut_at_the_last_dot_and_any_path_is_dropped(self):
        self.assertEqual("ADM-1042", student_photos.stem("ADM-1042.JPG"))
        self.assertEqual("ADM.10.42", student_photos.stem("ADM.10.42.png"))
        self.assertEqual("ADM-7", student_photos.stem("C:\\photos\\class 5\\ADM-7.jpg"))
        self.assertEqual("ADM-7", student_photos.stem("photos/ADM-7.jpeg"))

    def test_only_jpeg_and_png_names_count_as_photos(self):
        self.assertTrue(all(student_photos.is_image_name(n) for n in ("a.jpg", "a.JPEG", "a.png")))
        self.assertFalse(any(student_photos.is_image_name(n) for n in ("a.heic", "a.pdf", "a.jpg.exe", "jpg")))


class BulkTest(single.StudentPhotoTest):
    def setUp(self):
        super().setUp()
        self.slashed = factories.StudentFactory(class_section=self.section, admission_number="SPHS/26/01A01")
        self.left = factories.StudentFactory(
            class_section=self.section, admission_number="ADM-9", status=StudentStatus.INACTIVE
        )
        # Another school has an ADM-1 too; it must never be matched.
        self.theirs = factories.StudentFactory(
            class_section=factories.ClassSectionFactory(
                school_class=factories.SchoolClassFactory(school=self.elsewhere)
            ),
            admission_number="ADM-1",
        )

    def preview(self, user, names, **extra):
        return self.client_for(user).post(PREVIEW, {"file_names": names, **extra}, format="json")

    def store(self, user, files, **extra):
        return self.client_for(user).post(STORE, {"photos": files, **extra}, format="multipart")


class ThePreview(BulkTest):
    def test_each_name_is_matched_and_says_what_will_happen(self):
        self.post_photo(self.admin)  # ADM-1 already has a photo

        response = self.preview(
            self.admin, ["adm-1.jpg", "SPHS_26_01A01.png", "ADM-9.jpeg", "NOBODY.jpg", "notes.pdf"]
        )

        self.assertEqual(200, response.status_code, response.data)
        rows = {row["file_name"]: row for row in response.data["rows"]}
        self.assertEqual("replace", rows["adm-1.jpg"]["status"])
        self.assertTrue(rows["adm-1.jpg"]["student"]["has_photo"])
        self.assertEqual(self.student.id, rows["adm-1.jpg"]["student"]["id"])
        self.assertEqual("Grade 5 A", rows["adm-1.jpg"]["student"]["class_section_name"])
        self.assertEqual("new", rows["SPHS_26_01A01.png"]["status"])
        self.assertEqual("SPHS/26/01A01", rows["SPHS_26_01A01.png"]["student"]["admission_number"])
        self.assertEqual("new", rows["ADM-9.jpeg"]["status"], "an inactive student still matches")
        self.assertEqual("unmatched", rows["NOBODY.jpg"]["status"])
        self.assertEqual("not_an_image", rows["notes.pdf"]["status"])
        self.assertEqual(
            {"replace": 1, "new": 2, "unmatched": 1, "not_an_image": 1}, response.data["counts"]
        )

    def test_two_files_for_one_student_are_both_held_back(self):
        response = self.preview(self.admin, ["ADM-1.jpg", "adm_1.png", "ADM-9.jpg"])

        statuses = [row["status"] for row in response.data["rows"]]
        self.assertEqual(["duplicate", "duplicate", "new"], statuses)

    def test_two_students_whose_numbers_differ_only_by_slash_or_dash_are_not_guessed(self):
        factories.StudentFactory(class_section=self.section, admission_number="SPHS-26-01A01")

        row = self.preview(self.admin, ["SPHS-26-01A01.jpg"]).data["rows"][0]

        self.assertEqual("ambiguous", row["status"])
        self.assertIsNone(row["student"])

    def test_another_schools_numbers_never_match(self):
        row = self.preview(self.stranger, ["ADM-1.jpg"]).data["rows"][0]

        self.assertEqual(self.theirs.id, row["student"]["id"])
        self.assertEqual(
            "unmatched", self.preview(self.stranger, ["SPHS-26-01A01.jpg"]).data["rows"][0]["status"]
        )

    def test_nothing_is_written(self):
        self.preview(self.admin, ["ADM-1.jpg"])

        self.assertIsNone(Student.objects.get(pk=self.student.pk).photo_path)
        self.assertFalse(AuditLog.objects.filter(module="students").exists())

    def test_an_empty_or_malformed_list_is_refused(self):
        for body in ({"file_names": []}, {"file_names": "ADM-1.jpg"}, {"file_names": [1, 2]}, {}):
            response = self.client_for(self.admin).post(PREVIEW, body, format="json")
            self.assertEqual(422, response.status_code, body)
            self.assertIn("file_names", response.data["details"]["errors"])

    def test_too_many_names_at_once_are_refused(self):
        names = [f"A-{n}.jpg" for n in range(student_photos.MAX_PREVIEW_NAMES + 1)]

        self.assertEqual(422, self.preview(self.admin, names).status_code)


class TheUpload(BulkTest):
    def test_matched_photos_are_stored_and_each_file_gets_its_own_answer(self):
        self.post_photo(self.admin)  # ADM-1 already has one

        response = self.store(
            self.admin,
            [photo_file("ADM-1.jpg"), photo_file("sphs_26_01a01.jpg"), photo_file("NOBODY.jpg")],
        )

        self.assertEqual(200, response.status_code, response.data)
        results = {r["file_name"]: r for r in response.data["results"]}
        self.assertEqual("replaced", results["ADM-1.jpg"]["status"])
        self.assertEqual("added", results["sphs_26_01a01.jpg"]["status"])
        self.assertEqual(self.slashed.id, results["sphs_26_01a01.jpg"]["student_id"])
        self.assertEqual(("skipped", student_photos.NO_STUDENT), (results["NOBODY.jpg"]["status"], results["NOBODY.jpg"]["reason"]))
        self.assertIsNotNone(Student.objects.get(pk=self.slashed.pk).photo_path)

    def test_a_bad_file_is_reported_and_the_rest_are_still_kept(self):
        response = self.store(
            self.admin,
            [photo_file("ADM-1.jpg", b"not really a photo"), photo_file("ADM-9.jpg")],
        )

        results = {r["file_name"]: r for r in response.data["results"]}
        self.assertEqual("skipped", results["ADM-1.jpg"]["status"])
        self.assertEqual("The photo must be a JPEG or PNG image.", results["ADM-1.jpg"]["reason"])
        self.assertEqual("added", results["ADM-9.jpg"]["status"])
        self.assertIsNone(Student.objects.get(pk=self.student.pk).photo_path)
        self.assertIsNotNone(Student.objects.get(pk=self.left.pk).photo_path)

    def test_the_second_file_for_a_student_in_one_batch_is_skipped(self):
        response = self.store(self.admin, [photo_file("ADM-1.jpg"), photo_file("adm_1.jpg")])

        self.assertEqual(["added", "skipped"], [r["status"] for r in response.data["results"]])

    def test_a_file_that_is_not_a_photo_by_name_is_skipped(self):
        response = self.store(self.admin, [photo_file("ADM-1.gif", content_type="image/gif")])

        self.assertEqual(student_photos.NOT_AN_IMAGE, response.data["results"][0]["reason"])

    def test_the_photo_is_cut_to_passport_shape_like_a_single_one(self):
        self.store(self.admin, [photo_file("ADM-1.png", image_bytes(size=(800, 400)), "image/png")])

        self.assertEqual((300, 400), self.stored().size)

    def test_more_than_ten_files_are_refused_and_none_is_kept(self):
        files = [photo_file(f"ADM-1-{n}.jpg") for n in range(student_photos.MAX_FILES_PER_BATCH + 1)]

        response = self.store(self.admin, files)

        self.assertEqual(422, response.status_code)
        self.assertIn("photos", response.data["details"]["errors"])

    def test_no_files_is_refused(self):
        response = self.client_for(self.admin).post(STORE, {}, format="multipart")

        self.assertEqual(422, response.status_code)

    def test_each_student_is_audited_and_the_batch_is_summed_up(self):
        self.store(self.admin, [photo_file("ADM-1.jpg"), photo_file("ADM-9.jpg"), photo_file("NOBODY.jpg")])

        self.assertEqual(2, AuditLog.objects.filter(action="student.photo_changed").count())
        summary = AuditLog.objects.get(action="student_photos.bulk_uploaded")
        self.assertEqual({"added": 2, "replaced": 0, "skipped": 1}, summary.new_values)
        self.assertEqual((self.school.id, self.admin.id), (summary.school_id, summary.user_id))

    def test_another_schools_admin_reaches_only_their_own_students(self):
        response = self.store(self.stranger, [photo_file("ADM-1.jpg")])

        self.assertEqual(self.theirs.id, response.data["results"][0]["student_id"])
        self.assertIsNone(Student.objects.get(pk=self.student.pk).photo_path)
        self.assertIsNotNone(Student.objects.get(pk=self.theirs.pk).photo_path)


class WhoMayUploadInBulk(BulkTest):
    def test_a_school_admin_may(self):
        self.assertEqual(200, self.preview(self.admin, ["ADM-1.jpg"]).status_code)
        self.assertEqual(200, self.store(self.admin, [photo_file("ADM-1.jpg")]).status_code)

    def test_a_class_teacher_may_not_even_for_their_own_section(self):
        self.assertEqual(403, self.preview(self.class_teacher, ["ADM-1.jpg"]).status_code)
        self.assertEqual(403, self.store(self.class_teacher, [photo_file("ADM-1.jpg")]).status_code)
        self.assertIsNone(Student.objects.get(pk=self.student.pk).photo_path)

    def test_an_accountant_may_not(self):
        self.assertEqual(403, self.preview(self.accountant, ["ADM-1.jpg"]).status_code)
        self.assertEqual(403, self.store(self.accountant, [photo_file("ADM-1.jpg")]).status_code)

    def test_a_super_admin_names_the_school(self):
        refused = self.preview(self.root, ["ADM-1.jpg"])
        self.assertEqual(422, refused.status_code)
        self.assertIn("school_id", refused.data["details"]["errors"])

        response = self.store(self.root, [photo_file("ADM-1.jpg")], school_id=self.school.id)
        self.assertEqual(self.student.id, response.data["results"][0]["student_id"])
        self.assertEqual("added", response.data["results"][0]["status"])

    def test_a_school_admin_naming_another_school_still_gets_their_own(self):
        response = self.preview(self.admin, ["ADM-1.jpg"], school_id=self.elsewhere.id)

        self.assertEqual(self.student.id, response.data["rows"][0]["student"]["id"])

    def test_signing_in_is_required(self):
        self.assertEqual(401, APIClient().post(PREVIEW, {"file_names": ["a.jpg"]}, format="json").status_code)
        self.assertEqual(401, APIClient().post(STORE, {"photos": [photo_file("a.jpg")]}, format="multipart").status_code)


"""A student's photo on paper (docs/student-photos.md, P3): the admit card
and the Classic report card print it in their photo box, and print the empty
box as before when there is none.
"""

import base64
import io
import os
import re
import shutil
import tempfile

from django.core.files.storage import default_storage
from django.test import override_settings
from PIL import Image

from school import pdf_design, student_photos
from school.examinations import card_pdf
from school.models import Examination, ExaminationVersion

from . import test_examinations_api as exams
from . import test_report_card_classic as cards
from .test_profile_api import image_bytes


class WithPhotos:
    """Keeps the photos in a folder of their own, and gives a student one."""

    def use_a_media_folder(self):
        folder = tempfile.mkdtemp()
        self.addCleanup(shutil.rmtree, folder, ignore_errors=True)
        media = override_settings(MEDIA_ROOT=folder)
        media.enable()
        self.addCleanup(media.disable)

    def give_photo(self, student):
        data, extension = student_photos.prepare(_upload(image_bytes(fmt="JPEG", size=(600, 800))))
        student_photos.set_photo(student, data, extension)
        student.refresh_from_db()

    def save_sample(self, html: str, name: str):
        """Set PHOTO_SAMPLES to a folder to see the PDFs these tests print."""
        folder = os.environ.get("PHOTO_SAMPLES")

        if folder:
            os.makedirs(folder, exist_ok=True)
            with open(os.path.join(folder, f"{name}.pdf"), "wb") as handle:
                handle.write(pdf_design.render(html, name))

    def printed_photo(self, html: str) -> Image.Image:
        found = re.search(r'<img src="data:image/jpeg;base64,([^"]+)" width="(\d+)" height="(\d+)"', html)
        self.assertIsNotNone(found, "no photo in the document")

        return Image.open(io.BytesIO(base64.b64decode(found.group(1))))


def _upload(data: bytes):
    from django.core.files.uploadedfile import SimpleUploadedFile

    return SimpleUploadedFile("photo.jpg", data, content_type="image/jpeg")


class TheAdmitCard(WithPhotos, exams.ExamTestCase):
    def setUp(self):
        super().setUp()
        self.use_a_media_folder()

    def card_html(self, *, mono: bool = False) -> str:
        data = self.published()
        version = ExaminationVersion.objects.get(examination=Examination.objects.get(pk=data["id"]))
        snapshot = {**version.snapshot, "card_style": "mono" if mono else "colour"}
        card = card_pdf.Card(student=self.aarav, snapshot=snapshot, class_id=self.class8.id, version=1,
                             issued_on="11/17/2026")

        html = card_pdf.document([card], school=self.school, year_id=self.year.id)
        self.assertEqual(0, pdf_design.style_errors(html))

        return html

    def test_the_photo_is_printed_in_the_box(self):
        self.give_photo(self.aarav)

        html = self.card_html()
        self.save_sample(html, "admit-card-with-photo")

        self.assertNotIn("Student<br/>photo", html)
        self.assertIn('width="72" height="96"', html)
        self.assertEqual("RGB", self.printed_photo(html).mode)

    def test_a_black_and_white_card_prints_the_photo_in_grey(self):
        self.give_photo(self.aarav)

        html = self.card_html(mono=True)
        self.save_sample(html, "admit-card-mono-with-photo")

        self.assertEqual("L", self.printed_photo(html).mode)

    def test_with_no_photo_the_empty_box_prints_as_before(self):
        html = self.card_html()

        self.assertIn("Student<br/>photo", html)
        self.assertNotIn("data:image/jpeg", html)

    def test_a_photo_file_that_has_gone_missing_leaves_the_box_empty(self):
        self.give_photo(self.aarav)
        default_storage.delete(self.aarav.photo_path)

        self.assertIn("Student<br/>photo", self.card_html())

    def test_a_card_with_a_photo_still_renders_to_a_pdf(self):
        self.give_photo(self.aarav)
        data = self.published()

        response = self.card(data["id"], self.aarav)

        self.assertEqual(200, response.status_code)
        self.assertTrue(response.content.startswith(b"%PDF"))


class TheClassicReportCard(WithPhotos, cards.CardTestCase):
    def setUp(self):
        super().setUp()
        self.use_a_media_folder()

    def test_the_photo_is_printed_in_the_box(self):
        self.scale()
        self.give_photo(self.student)

        html = self.html()
        self.save_sample(html, "report-card-with-photo")

        self.assertNotIn("STUDENT<br/>PHOTO", html)
        self.assertIn('width="60" height="80"', html)
        self.printed_photo(html)

    def test_with_no_photo_the_empty_box_prints_as_before(self):
        self.scale()

        self.assertIn("STUDENT<br/>PHOTO", self.html())

    def test_a_report_card_with_a_photo_renders_to_a_pdf(self):
        self.scale()
        self.give_photo(self.student)

        pdf = pdf_design.render(self.html(), "report-card.pdf")

        self.assertTrue(pdf.startswith(b"%PDF"))

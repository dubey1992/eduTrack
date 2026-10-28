"""The shared PDF look (school/pdf_design.py, docs/pdf-design.md): every piece
leaves out what has no value, escapes what people typed, and the whole page
renders to a real PDF with a running footer - in portrait and landscape."""

import types
from unittest import mock

from django.test import SimpleTestCase

from school import pdf_design


def school(**fields):
    defaults = dict(
        name="Sunrise & Sons School", address="12 MG Road", city="Pune", state="Maharashtra", postal_code="411001",
        country="India", phone="+91 98000 00001", email="office@sunrise.example", registration_number="REG-77",
        logo_url=None,
    )
    return types.SimpleNamespace(**{**defaults, **fields})


class SmallPieces(SimpleTestCase):
    def test_a_fact_without_a_value_is_left_out(self):
        for value in (None, "", "   "):
            with self.subTest(value=value):
                self.assertEqual("", pdf_design.fact("Roll no.", value))

        self.assertIn("Roll no.", pdf_design.fact("Roll no.", 0))

    def test_facts_keep_only_the_lines_with_values(self):
        html = pdf_design.facts([("Name", "Asha"), ("Roll no.", None), ("Class", "8 - A")])

        self.assertIn("Asha", html)
        self.assertIn("8 - A", html)
        self.assertNotIn("Roll no.", html)

    def test_joined_skips_the_empty_parts(self):
        self.assertEqual("Pune, India", pdf_design.joined(None, "Pune", "", "  ", "India"))
        self.assertEqual("a · b", pdf_design.joined("a", None, "b", separator=" · "))

    def test_typed_text_is_escaped_everywhere(self):
        for html in (
            pdf_design.fact("Note", "<b>bold</b> & co"),
            pdf_design.stamp("CANCELLED", ["Reason: <script>"]),
            pdf_design.tiles([{"label": "<x>", "value": "1 & 2"}]),
            pdf_design.signatures(["Class teacher <A>"]),
            pdf_design.totals_panel("Net pay", "INR 1", "One & only"),
            pdf_design.closing(["<i>end</i>"]),
            pdf_design.running_footer("Sunrise & Sons"),
            pdf_design.section("Fees & dues"),
        ):
            with self.subTest(html=html[:40]):
                self.assertNotIn("<script>", html)
                self.assertNotIn("<b>bold", html)
                self.assertNotIn("<i>end", html)
                self.assertNotIn("<x>", html)
                self.assertIn("&amp;", html + "&amp;")


class TheBand(SimpleTestCase):
    def test_a_school_band_carries_its_name_contact_lines_title_and_number(self):
        html = pdf_design.school_band(school(), "PAYSLIP", "PSL-000060", "September 2026")

        for text in ("Sunrise &amp; Sons School", "12 MG Road, Pune, Maharashtra, 411001, India",
                     "Phone +91 98000 00001, office@sunrise.example", "Reg. no. REG-77", "PAYSLIP", "PSL-000060",
                     "September 2026"):
            self.assertIn(text, html)

    def test_lines_a_school_does_not_have_are_left_out(self):
        html = pdf_design.school_band(
            school(phone=None, email=None, registration_number=None, address=None, city=None, state=None,
                   postal_code=None, country=None),
            "FEE RECEIPT",
        )

        self.assertNotIn("Phone", html)
        self.assertNotIn("Reg. no.", html)
        self.assertNotIn("school-line", html)
        self.assertNotIn("doc-number", html)

    def test_a_logo_is_inlined_and_one_that_cannot_be_fetched_is_simply_left_out(self):
        self.assertNotIn("<img", pdf_design.school_band(school(logo_url="file:///etc/passwd"), "X"))

        with mock.patch.object(pdf_design, "logo_data_uri", return_value="data:image/png;base64,AAAA"):
            self.assertIn('<img src="data:image/png;base64,AAAA"', pdf_design.school_band(school(logo_url="x"), "X"))

    def test_only_http_logos_are_fetched(self):
        for url in (None, "", "file:///etc/passwd", "ftp://host/logo.png", "javascript:alert(1)"):
            with self.subTest(url=url):
                self.assertIsNone(pdf_design.logo_data_uri(url))

    def test_a_logo_that_fails_or_is_not_an_image_costs_only_the_logo(self):
        with mock.patch("urllib.request.urlopen", side_effect=OSError("timed out")):
            self.assertIsNone(pdf_design.logo_data_uri("https://example.invalid/logo.png"))

        response = mock.MagicMock()
        response.__enter__.return_value = response
        response.headers.get_content_type.return_value = "text/html"
        response.read.return_value = b"<html>"

        with mock.patch("urllib.request.urlopen", return_value=response):
            self.assertIsNone(pdf_design.logo_data_uri("https://example.invalid/logo.png"))

        response.headers.get_content_type.return_value = "image/png"
        response.read.return_value = b"\x89PNG"

        with mock.patch("urllib.request.urlopen", return_value=response):
            self.assertEqual("data:image/png;base64,iVBORw==",
                             pdf_design.logo_data_uri("https://example.invalid/logo.png"))


class Blocks(SimpleTestCase):
    def test_tiles_are_laid_out_in_rows_with_the_last_padded(self):
        html = pdf_design.tiles([{"label": f"L{n}", "value": n} for n in range(5)], per_row=4)

        self.assertEqual(2, html.count("<tr>"))
        self.assertEqual(8, html.count('width="25%"'))
        self.assertEqual("", pdf_design.tiles([]))

    def test_a_tile_shows_nought_rather_than_nothing(self):
        html = pdf_design.tiles([{"label": "Half days", "value": 0}])

        self.assertIn('style="color: #374151;">0</div>', html)

    def test_a_tile_takes_its_tone(self):
        self.assertIn(pdf_design.TONES["danger"][0], pdf_design.tiles([{"label": "Overdue", "value": 3,
                                                                         "tone": "danger"}]))

    def test_a_table_repeats_its_heading_stripes_its_rows_and_right_aligns_numbers(self):
        html = pdf_design.table(
            [("Student", "40%", False), ("Amount", None, True)],
            [["Asha", "10.00"], ["Kabir", "20.00"]],
            total=["Total", "30.00"],
        )

        self.assertIn('repeat="1"', html)
        self.assertIn('<th width="40%">Student</th>', html)
        self.assertIn('<th class="num">Amount</th>', html)
        self.assertEqual(1, html.count('class="zebra"'))
        self.assertIn('<tr class="total">', html)
        self.assertIn('<td class="num">30.00</td>', html)

    def test_an_empty_table_says_so_instead(self):
        self.assertIn("No payslips this month.", pdf_design.table([("A", None, False)], [], empty="No payslips this month."))

    def test_signatures_share_the_width(self):
        html = pdf_design.signatures(["Class teacher", "Principal", "Parent"])

        self.assertEqual(3, html.count('width="33%"'))
        self.assertEqual("", pdf_design.signatures([]))

    def test_the_totals_panel_prints_words_only_when_given(self):
        self.assertIn("Rupees Ten Only", pdf_design.totals_panel("Net pay", "INR 10.00", "Rupees Ten Only"))
        self.assertNotIn("words", pdf_design.totals_panel("Net pay", "INR 10.00"))


class ThePage(SimpleTestCase):
    def body(self):
        return (
            pdf_design.school_band(school(), "PAYSLIP", "PSL-1")
            + pdf_design.section("Summary")
            + pdf_design.tiles([{"label": "Net pay", "value": "INR 34,200.00", "tone": "success"}])
            + pdf_design.table([("Earning", None, False), ("Amount", None, True)],
                               [[f"Line {n}", "1.00"] for n in range(120)])
            + pdf_design.signatures(["Accountant", "Principal"])
            + pdf_design.closing(["Computer generated.", "Powered by School365ai"])
        )

    def test_portrait_and_landscape_both_render_to_a_pdf_with_page_numbers(self):
        for landscape in (False, True):
            with self.subTest(landscape=landscape):
                html = pdf_design.page("Payslip", self.body(), footer="Sunrise - Payslip PSL-1", landscape=landscape)
                pdf = pdf_design.render(html, "payslip.pdf")

                self.assertTrue(pdf.startswith(b"%PDF"))
                self.assertIn("a4 landscape" if landscape else "a4 portrait", html)
                self.assertIn("<pdf:pagecount>", html)
                # 120 rows run over more than one page.
                self.assertGreater(pdf.count(b"/Type /Page\n") + pdf.count(b"/Type /Page\r") +
                                   pdf.count(b"/Type /Page "), 1)

    def test_the_shared_styles_never_leave_a_cell_unstyled(self):
        html = pdf_design.page("Payslip", self.body(), footer="f")

        self.assertEqual(0, pdf_design.style_errors(html))

    def test_style_errors_catches_a_repeated_selector(self):
        # The engine bug it exists for: the same selector twice, both
        # matching one cell.
        html = pdf_design.page("X", self.body(), footer="f", extra_styles=".items td { font-size: 8pt; }")

        self.assertGreater(pdf_design.style_errors(html), 0)

    def test_a_page_carries_its_own_styles_after_the_shared_ones(self):
        html = pdf_design.page("X", "", footer="f", extra_styles=".mine { color: red; }")

        self.assertLess(html.index(".band td"), html.index(".mine"))

    def test_a_document_that_cannot_render_says_which(self):
        with mock.patch.object(pdf_design.pisa, "CreatePDF", return_value=types.SimpleNamespace(err=1)):
            with self.assertRaisesMessage(RuntimeError, "Could not render payslip.pdf"):
                pdf_design.render("<p>x</p>", "payslip.pdf")

"""Draws backend-python/school/public_site_assets/og-image.png: the card shown when a link to
school365ai.com is shared on WhatsApp, LinkedIn, X or Facebook
(docs/seo.md, S1).

1200 x 630, the size every one of them expects. In the Warm Editorial
design (2026-11-14): the plum ground of the app's sign-in panel with its
rose and coral glows, the favicon's mark (scripts/site_icon.py), the name
with "ai" in coral, and the sign-in page's line in the serif.

    python scripts/og_image.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter, ImageFont

from site_icon import render

WIDTH, HEIGHT = 1200, 630
OUT = Path(__file__).resolve().parent.parent / "backend-python" / "school" / "public_site_assets" / "og-image.png"

PLUM = (0x49, 0x2B, 0x4E)
ROSE = (0xA3, 0x3D, 0x63)
CORAL = (0xE6, 0x95, 0x68)
PEACH = (0xF5, 0xB1, 0x8C)   # the italic "simpler." on the sign-in panel
WHITE = (255, 255, 255)
LILAC = (0xF0, 0xE1, 0xED)   # the sign-in panel's body text

FEATURES = "Attendance  ·  Fees  ·  Transport  ·  Timetable  ·  Payroll  ·  Reports"


def font(names: list[str], size: int) -> ImageFont.FreeTypeFont:
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue

    return ImageFont.load_default(size)


# Georgia is the website's heading face; Segoe UI stands in for DM Sans,
# which Windows does not ship.
SERIF = ["georgia.ttf", "DejaVuSerif.ttf"]
SERIF_ITALIC = ["georgiai.ttf", "DejaVuSerif-Italic.ttf"]
BOLD = ["segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"]
REGULAR = ["segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"]


def ground() -> Image.Image:
    """Plum, with a soft rose glow at the top right and a coral one at the
    bottom left, as on the sign-in panel."""
    image = Image.new("RGB", (WIDTH, HEIGHT), PLUM)
    glow = Image.new("RGBA", (WIDTH, HEIGHT), (0, 0, 0, 0))
    draw = ImageDraw.Draw(glow)
    draw.ellipse([820, -330, 1440, 290], fill=ROSE + (120,))
    draw.ellipse([-200, 400, 260, 860], fill=CORAL + (90,))
    glow = glow.filter(ImageFilter.GaussianBlur(40))
    image.paste(glow, (0, 0), glow)
    return image


def main() -> None:
    image = ground()
    draw = ImageDraw.Draw(image)

    mark = render(112, full_bleed=False)
    image.paste(mark, (84, 84), mark)

    name = font(BOLD, 60)
    draw.text((218, 104), "School365", font=name, fill=WHITE)
    draw.text((218 + draw.textlength("School365", font=name), 104), "ai", font=name, fill=CORAL)

    headline = font(SERIF, 76)
    italic = font(SERIF_ITALIC, 76)
    draw.text((84, 238), "Every school day,", font=headline, fill=WHITE)
    draw.text((84, 330), "a little ", font=headline, fill=WHITE)
    draw.text((84 + draw.textlength("a little ", font=headline), 330), "simpler.", font=italic, fill=PEACH)

    draw.text((86, 476), FEATURES, font=font(REGULAR, 30), fill=LILAC)
    draw.text((86, 534), "school365ai.com", font=font(BOLD, 28), fill=CORAL)

    image.save(OUT, optimize=True)
    print(f"Wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()

"""Draws frontend/web/og-image.png: the card shown when a link to
school365ai.com is shared on WhatsApp, LinkedIn, X or Facebook
(docs/seo.md, S1).

1200 x 630, the size every one of them expects. The mark is the same
mortarboard as the favicon and the loading screen (frontend/web/index.html).

    python scripts/og_image.py
"""

from __future__ import annotations

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

WIDTH, HEIGHT = 1200, 630
OUT = Path(__file__).resolve().parent.parent / "frontend" / "web" / "og-image.png"

BLUE_TOP = (37, 99, 235)      # #2563EB, the app's primary
BLUE_BOTTOM = (29, 78, 216)   # #1D4ED8
GOLD = (251, 191, 36)         # #FBBF24, the tassel
WHITE = (255, 255, 255)
SOFT_WHITE = (219, 234, 254)  # #DBEAFE

FEATURES = "Attendance  ·  Fees  ·  Transport  ·  Timetable  ·  Payroll  ·  Reports"


def font(names: list[str], size: int) -> ImageFont.FreeTypeFont:
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue

    return ImageFont.load_default(size)


BOLD = ["seguisb.ttf", "segoeuib.ttf", "arialbd.ttf", "DejaVuSans-Bold.ttf"]
REGULAR = ["segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"]


def gradient() -> Image.Image:
    image = Image.new("RGB", (WIDTH, HEIGHT))
    draw = ImageDraw.Draw(image)

    for y in range(HEIGHT):
        t = y / (HEIGHT - 1)
        colour = tuple(round(a + (b - a) * t) for a, b in zip(BLUE_TOP, BLUE_BOTTOM))
        draw.line([(0, y), (WIDTH, y)], fill=colour)

    return image


def mark(draw: ImageDraw.ImageDraw, left: int, top: int, size: int) -> None:
    """The mortarboard, drawn on a 100-unit grid like the SVG."""

    def at(x: float, y: float) -> tuple[float, float]:
        return left + x * size / 100, top + y * size / 100

    # The cap's band, a little transparent in the SVG; a paler white here.
    draw.polygon([at(30, 50), at(30, 66), at(50, 74), at(70, 66), at(70, 50)], fill=SOFT_WHITE)
    # The board.
    draw.polygon([at(50, 24), at(86, 41), at(50, 58), at(14, 41)], fill=WHITE)
    # The tassel's cord and the tassel.
    width = max(2, round(3.5 * size / 100))
    draw.line([at(50, 41), at(78, 45)], fill=GOLD, width=width)
    draw.line([at(78, 45), at(78, 65)], fill=GOLD, width=width)
    r = 4.5 * size / 100
    cx, cy = at(78, 65)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD)
    r = 3 * size / 100
    cx, cy = at(50, 41)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD)


def main() -> None:
    image = gradient()
    draw = ImageDraw.Draw(image)

    mark(draw, left=80, top=150, size=200)

    draw.text((300, 175), "School365ai", font=font(BOLD, 96), fill=WHITE)
    draw.text((304, 295), "School management software", font=font(BOLD, 44), fill=SOFT_WHITE)
    draw.text((84, 470), FEATURES, font=font(REGULAR, 34), fill=WHITE)
    draw.text((84, 540), "school365ai.com", font=font(BOLD, 30), fill=GOLD)

    image.save(OUT, optimize=True)
    print(f"Wrote {OUT} ({OUT.stat().st_size // 1024} KB)")


if __name__ == "__main__":
    main()

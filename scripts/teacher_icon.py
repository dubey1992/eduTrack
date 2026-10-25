"""Draws the teacher app's launcher icon at every density.

    python scripts/teacher_icon.py

An open book with an amber ribbon on the brand's teal - the same shape as
`TeacherMark` in frontend/lib/core/widgets/teacher_mark.dart, on the same
100 x 100 grid, so the icon on the launcher and the mark in the app are one
drawing. Drawn here rather than exported from a design tool so it can be
regenerated in one command, with no binary asset nobody can edit.

Every layer is drawn at 8x and scaled down, which is what gives the curves
smooth edges; PIL draws without anti-aliasing otherwise.

Writes into android/app/src/teacher/res/:
- `ic_launcher_foreground.png` - the mark on transparency, for the adaptive
  icon (the teal behind it is a colour, ic_launcher_background);
- `ic_launcher_monochrome.png` - the mark as one flat shape, for Android 13
  themed icons, which tint it to the wallpaper;
- `ic_launcher.png` - the legacy square icon, mark on teal.
"""

from pathlib import Path

from PIL import Image, ImageDraw

RES = Path(__file__).resolve().parent.parent / "frontend" / "android" / "app" / "src" / "teacher" / "res"
TEAL = (0x0F, 0x76, 0x6E, 255)
TEAL_DEEP = (0x11, 0x5E, 0x59, 255)
PAPER = (255, 255, 255, 255)
AMBER = (0xF5, 0x9E, 0x0B, 255)

SUPERSAMPLE = 8

# dp per density bucket: legacy icon 48dp, adaptive layers 108dp.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def quad(p0, c, p1, steps=24):
    """Points along a quadratic Bezier, as Flutter's quadraticBezierTo draws."""
    return [
        (
            (1 - t) ** 2 * p0[0] + 2 * (1 - t) * t * c[0] + t**2 * p1[0],
            (1 - t) ** 2 * p0[1] + 2 * (1 - t) * t * c[1] + t**2 * p1[1],
        )
        for t in (i / steps for i in range(steps + 1))
    ]


def draw_mark(size: int, *, background, pages=PAPER, ink=TEAL, ribbon=AMBER, area=0.62, cut=False) -> Image.Image:
    """The book centred in a square of `size` px, filling `area` of it.

    Coordinates follow _BookPainter: a 100-unit grid, spine at x=50.
    With `cut`, the lines and the fold are cut out of the pages rather than
    drawn on them - the one-colour version for themed icons.
    """
    big = size * SUPERSAMPLE
    image = Image.new("RGBA", (big, big), background)
    draw = ImageDraw.Draw(image)

    span = big * area
    origin = (big - span) / 2

    def p(x, y):
        return (origin + x * span / 100, origin + y * span / 100)

    def page(outer):
        mid = (50 + outer) / 2
        top = quad((50, 34), (mid, 20), (outer, 25))
        bottom = quad((outer, 73), (mid, 68), (50, 82))
        return [p(x, y) for x, y in top + bottom]

    draw.polygon(page(8), fill=pages)
    draw.polygon(page(92), fill=pages)

    if cut:
        ink = (0, 0, 0, 0)

    if ink is not None:
        width = max(1, round(2.8 * span / 100))
        for y in (41, 50, 59):
            for line in (quad((18, y - 4), (31, y - 6.5), (43, y - 1)), quad((57, y - 1), (69, y - 6.5), (82, y - 4))):
                points = [p(x, yy) for x, yy in line]
                draw.line(points, fill=ink, width=width, joint="curve")
                radius = width / 2
                for end in (points[0], points[-1]):
                    draw.ellipse([end[0] - radius, end[1] - radius, end[0] + radius, end[1] + radius], fill=ink)
        # The fold.
        fold = ink if cut else ink[:3] + (90,)
        draw.line([p(50, 35), p(50, 81)], fill=fold, width=max(1, round((2.4 if cut else 1.6) * span / 100)))

    if ribbon is not None:
        draw.polygon([p(70, 23.5), p(79, 24.5), p(79, 45), p(74.5, 40.5), p(70, 45)], fill=ribbon)

    return image.resize((size, size), Image.LANCZOS)


def gradient_square(size: int) -> Image.Image:
    """The teal tile for the legacy icon, top left to bottom right."""
    tile = Image.new("RGBA", (size, size))
    pixels = tile.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            pixels[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(TEAL, TEAL_DEEP))
    return tile


def main() -> None:
    for bucket, scale in DENSITIES.items():
        folder = RES / f"mipmap-{bucket}"
        folder.mkdir(parents=True, exist_ok=True)
        layer = int(108 * scale)

        # Adaptive layers: the mark inside the 66dp safe zone of 108dp.
        draw_mark(layer, background=(0, 0, 0, 0)).save(folder / "ic_launcher_foreground.png")
        draw_mark(layer, background=(0, 0, 0, 0), pages=PAPER, ribbon=None, cut=True).save(
            folder / "ic_launcher_monochrome.png"
        )

        # Legacy: the whole square shows, so the mark fills more of it.
        legacy_size = int(48 * scale)
        tile = gradient_square(legacy_size)
        tile.alpha_composite(draw_mark(legacy_size, background=(0, 0, 0, 0), area=0.74))
        # Rounded like the in-app tile (TeacherMark, tile: true), for the
        # launchers that show a legacy icon as it is.
        big = legacy_size * SUPERSAMPLE
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=big * 0.22, fill=255)
        legacy = Image.new("RGBA", (legacy_size, legacy_size), (0, 0, 0, 0))
        legacy.paste(tile, (0, 0), mask.resize((legacy_size, legacy_size), Image.LANCZOS))
        legacy.save(folder / "ic_launcher.png")
        print(f"{bucket}: {folder}")


if __name__ == "__main__":
    main()

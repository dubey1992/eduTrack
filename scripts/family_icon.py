"""Draws the Family app's launcher icon at every density.

    python scripts/family_icon.py

A house with a heart in its doorway, on the School365ai blue - the same
shape as `FamilyMark` in frontend/lib/core/widgets/family_mark.dart, on the
same 100 x 100 grid, so the launcher icon and the mark in the app are one
drawing (docs/parent-student-app.md, "Look and feel"). Built the way
scripts/teacher_icon.py is: every layer at 8x, scaled down for smooth edges.

Writes into android/app/src/family/res/:
- `ic_launcher_foreground.png` - the mark on transparency, for the adaptive
  icon (the blue behind it is a colour, ic_launcher_background);
- `ic_launcher_monochrome.png` - the mark as one flat shape with the heart
  cut out, for Android 13 themed icons;
- `ic_launcher.png` - the legacy square icon, mark on blue.
"""

from pathlib import Path

from PIL import Image, ImageDraw

RES = Path(__file__).resolve().parent.parent / "frontend" / "android" / "app" / "src" / "family" / "res"
BLUE = (0x6D, 0x3B, 0xD8, 255)  # the logo's violet (slice B1, 2026-11-24)
BLUE_DEEP = (0x4C, 0x25, 0xA8, 255)
WHITE = (255, 255, 255, 255)
CORAL = (0xFB, 0x71, 0x85, 255)
CLEAR = (0, 0, 0, 0)

SUPERSAMPLE = 8

# dp per density bucket: legacy icon 48dp, adaptive layers 108dp.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}

# The house, on the 100-unit grid FamilyMark uses.
HOUSE = [(50, 16), (90, 49), (78, 49), (78, 84), (22, 84), (22, 49), (10, 49)]
# The heart: two lobes and the point.
LOBES = [(42.5, 60, 8), (57.5, 60, 8)]
POINT = [(34.9, 62.6), (65.1, 62.6), (50, 77)]


def draw_mark(size: int, *, background, house=WHITE, heart=CORAL, area=0.66) -> Image.Image:
    """The house centred in a square of `size` px, filling `area` of it."""
    big = size * SUPERSAMPLE
    image = Image.new("RGBA", (big, big), background)
    draw = ImageDraw.Draw(image)

    span = big * area
    origin = (big - span) / 2

    def p(x, y):
        return (origin + x * span / 100, origin + y * span / 100)

    draw.polygon([p(x, y) for x, y in HOUSE], fill=house)

    for x, y, r in LOBES:
        left, top = p(x - r, y - r)
        right, bottom = p(x + r, y + r)
        draw.ellipse([left, top, right, bottom], fill=heart)
    draw.polygon([p(x, y) for x, y in POINT], fill=heart)

    return image.resize((size, size), Image.LANCZOS)


def gradient_square(size: int) -> Image.Image:
    """The blue tile for the legacy icon, top left to bottom right."""
    tile = Image.new("RGBA", (size, size))
    pixels = tile.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            pixels[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(BLUE, BLUE_DEEP))
    return tile


def main() -> None:
    for bucket, scale in DENSITIES.items():
        folder = RES / f"mipmap-{bucket}"
        folder.mkdir(parents=True, exist_ok=True)
        layer = int(108 * scale)

        # Adaptive layers: the mark inside the 66dp safe zone of 108dp.
        draw_mark(layer, background=CLEAR).save(folder / "ic_launcher_foreground.png")
        draw_mark(layer, background=CLEAR, heart=CLEAR).save(folder / "ic_launcher_monochrome.png")

        # Legacy: the whole square shows, so the mark fills more of it.
        legacy_size = int(48 * scale)
        tile = gradient_square(legacy_size)
        tile.alpha_composite(draw_mark(legacy_size, background=CLEAR, area=0.74))
        big = legacy_size * SUPERSAMPLE
        mask = Image.new("L", (big, big), 0)
        ImageDraw.Draw(mask).rounded_rectangle([0, 0, big - 1, big - 1], radius=big * 0.22, fill=255)
        legacy = Image.new("RGBA", (legacy_size, legacy_size), CLEAR)
        legacy.paste(tile, (0, 0), mask.resize((legacy_size, legacy_size), Image.LANCZOS))
        legacy.save(folder / "ic_launcher.png")
        print(f"{bucket}: {folder}")


if __name__ == "__main__":
    main()

"""Draws the Driver app's launcher icon at every density.

    python scripts/driver_icon.py

The shuttle from the splash animation (assets/driver/shuttle-run.gif), side
on with its nose to the right, in white on the brand blue - the same
drawing as `DriverMark` in frontend/lib/core/widgets/driver_mark.dart, on
the same 100 x 100 grid, so the launcher and the app show one shuttle.
It replaces the graduation cap the driver app first shipped with: a cap
says "school"; the driver's app is the bus.

Every layer is drawn at 8x and scaled down for smooth edges.

Writes into android/app/src/main/res/ (the driver flavour uses main's):
- `ic_launcher_foreground.png` - the shuttle on transparency, for the
  adaptive icon (the blue behind it is ic_launcher_background);
- `ic_launcher_monochrome.png` - one flat shape, for Android 13 themed icons;
- `ic_launcher.png` - the legacy icon, shuttle on a blue rounded square.
And, with --store <folder>, a 512 x 512 icon for the Play listing.
"""

import sys
from pathlib import Path

from PIL import Image, ImageDraw

RES = Path(__file__).resolve().parent.parent / "frontend" / "android" / "app" / "src" / "main" / "res"
BLUE = (0x25, 0x63, 0xEB, 255)
BLUE_DEEP = (0x1D, 0x4E, 0xD8, 255)
WHITE = (255, 255, 255, 255)
SKIRT = (0xDB, 0xEA, 0xFE, 255)
GLASS = (0x1D, 0x4E, 0xD8, 255)
TYRE = (0x0F, 0x17, 0x2A, 255)
HUB = (0xCB, 0xD5, 0xE1, 255)
AMBER = (0xF5, 0x9E, 0x0B, 255)

SUPERSAMPLE = 8
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def draw_shuttle(size: int, *, area: float = 0.62, flat=None) -> Image.Image:
    """The shuttle on transparency, filling `area` of the square. With
    `flat`, every part is that one colour - the themed-icon layer."""
    big = size * SUPERSAMPLE
    image = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)
    span = big * area
    origin = (big - span) / 2

    def p(x, y):
        return (origin + x * span / 100, origin + y * span / 100)

    def box(x0, y0, x1, y1, radius, fill):
        (a, b), (c, d) = p(x0, y0), p(x1, y1)
        draw.rounded_rectangle([a, b, c, d], radius=radius * span / 100, fill=flat or fill)

    def circle(cx, cy, r, fill):
        (a, b), (c, d) = p(cx - r, cy - r), p(cx + r, cy + r)
        draw.ellipse([a, b, c, d], fill=flat or fill)

    # Body, then the darker lower skirt so it reads as a vehicle.
    box(2, 22, 98, 74, 12, WHITE)
    box(2, 58, 98, 74, 7, SKIRT)
    # Windows along the side, and the door at the back where children board.
    if flat is None:
        for i in range(4):
            left = 20 + i * 19
            box(left, 30, left + 13, 46, 3, GLASS)
        box(6, 32, 14, 66, 2, GLASS)
        # The headlight.
        circle(93, 52, 4, AMBER)
    # Wheels: tyre, hub.
    for cx in (24, 76):
        circle(cx, 75, 11, TYRE if flat is None else flat)
        if flat is None:
            circle(cx, 75, 5, HUB)

    return image.resize((size, size), Image.LANCZOS)


def gradient_square(size: int, radius_ratio: float = 0.22) -> Image.Image:
    """The legacy icon's tile: brand blue deepening to the corner."""
    big = size * SUPERSAMPLE
    tile = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    fill = Image.new("RGBA", (big, big), BLUE)
    draw = ImageDraw.Draw(fill)
    for y in range(big):
        t = y / big
        colour = tuple(int(BLUE[i] + (BLUE_DEEP[i] - BLUE[i]) * t) for i in range(3)) + (255,)
        draw.line([(0, y), (big, y)], fill=colour)
    mask = Image.new("L", (big, big), 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, big, big], radius=big * radius_ratio, fill=255)
    tile.paste(fill, (0, 0), mask)
    return tile.resize((size, size), Image.LANCZOS)


def main() -> None:
    for name, scale in DENSITIES.items():
        folder = RES / f"mipmap-{name}"
        folder.mkdir(parents=True, exist_ok=True)

        adaptive = round(108 * scale)
        # The adaptive layer is 108dp, of which only the middle 66dp is
        # sure to show: the shuttle sits inside that.
        draw_shuttle(adaptive, area=0.56).save(folder / "ic_launcher_foreground.png")
        draw_shuttle(adaptive, area=0.56, flat=WHITE).save(folder / "ic_launcher_monochrome.png")

        legacy = round(48 * scale)
        tile = gradient_square(legacy)
        tile.alpha_composite(draw_shuttle(legacy, area=0.7))
        tile.save(folder / "ic_launcher.png")

    if "--store" in sys.argv:
        out = Path(sys.argv[sys.argv.index("--store") + 1])
        out.mkdir(parents=True, exist_ok=True)
        store = Image.new("RGBA", (512, 512), BLUE)
        draw = ImageDraw.Draw(store)
        for y in range(512):
            t = y / 512
            draw.line([(0, y), (512, y)], fill=tuple(int(BLUE[i] + (BLUE_DEEP[i] - BLUE[i]) * t) for i in range(3)) + (255,))
        store.alpha_composite(draw_shuttle(512, area=0.66))
        store.convert("RGB").save(out / "driver-icon-512.png")

    print("written to", RES)


if __name__ == "__main__":
    main()

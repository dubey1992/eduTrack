"""Draws the teacher app's launcher icon at every density.

    python scripts/teacher_icon.py

An open book on the flavour's green (docs/teacher-app.md, T0). Drawn here
rather than exported from a design tool so the mark can be regenerated in
one command when the colour or the shape changes, and so there is no
binary asset nobody can edit. Writes into android/app/src/teacher/res/,
the adaptive foreground (the mark alone on transparency) and the legacy
square icon (mark on the green) that older launchers use.
"""

from pathlib import Path

from PIL import Image, ImageDraw

RES = Path(__file__).resolve().parent.parent / "frontend" / "android" / "app" / "src" / "teacher" / "res"
GREEN = (0x0F, 0x76, 0x6E, 255)
PAPER = (255, 255, 255, 255)
LINE = (0x0F, 0x76, 0x6E, 255)

# dp per density bucket: legacy icon 48dp, adaptive foreground 108dp.
DENSITIES = {"mdpi": 1, "hdpi": 1.5, "xhdpi": 2, "xxhdpi": 3, "xxxhdpi": 4}


def draw_book(size: int, *, background) -> Image.Image:
    """The mark inside the adaptive-icon safe zone (the middle 66%)."""
    image = Image.new("RGBA", (size, size), background)
    draw = ImageDraw.Draw(image)
    s = size / 108  # work in the 108dp adaptive grid

    def p(x, y):
        return (x * s, y * s)

    # Two pages meeting at a spine, drawn as rounded quads.
    left = [p(26, 36), p(52, 42), p(52, 78), p(26, 72)]
    right = [p(82, 36), p(56, 42), p(56, 78), p(82, 72)]
    draw.polygon(left, fill=PAPER)
    draw.polygon(right, fill=PAPER)
    # The spine.
    draw.rectangle([p(52, 42), p(56, 78)], fill=PAPER)
    # Text lines on each page, so it reads as a book at 48px.
    for y in (50, 57, 64):
        draw.line([p(31, y + 1), p(47, y + 2.5)], fill=LINE, width=max(1, int(2.6 * s)))
        draw.line([p(61, y + 2.5), p(77, y + 1)], fill=LINE, width=max(1, int(2.6 * s)))
    # A ribbon bookmark on the right page.
    draw.polygon([p(70, 36), p(76, 37.5), p(76, 50), p(73, 47.5), p(70, 50)], fill=(0xF5, 0x9E, 0x0B, 255))
    return image


def main() -> None:
    for bucket, scale in DENSITIES.items():
        folder = RES / f"mipmap-{bucket}"
        folder.mkdir(parents=True, exist_ok=True)
        foreground = draw_book(int(108 * scale), background=(0, 0, 0, 0))
        foreground.save(folder / "ic_launcher_foreground.png")
        legacy = draw_book(int(108 * scale), background=GREEN)
        # Legacy icons show the whole square: crop to the safe zone so the
        # mark fills it the way the masked adaptive icon does.
        inset = int(18 * scale)
        legacy = legacy.crop((inset, inset, legacy.width - inset, legacy.height - inset)).resize(
            (int(48 * scale), int(48 * scale)), Image.LANCZOS
        )
        legacy.save(folder / "ic_launcher.png")
        print(f"{bucket}: {folder / 'ic_launcher.png'}")


if __name__ == "__main__":
    main()

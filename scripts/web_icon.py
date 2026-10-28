"""Draws the website's favicon and app icons.

    python scripts/web_icon.py

A white mortarboard on the brand's blue (#2563EB) - the mark the website
shows beside its name in the header, the sign-in panel and the footer. These
files were Flutter's own logo, left over from the project template, until
2026-10-28. Drawn here rather than exported from a design tool so they can
be regenerated in one command, like the phone apps' icons
(scripts/driver_icon.py, scripts/teacher_icon.py).

Every layer is drawn at 8x and scaled down, which is what gives the edges
their smoothness; PIL draws without anti-aliasing otherwise.

Writes into frontend/web/:
- `favicon.png` (64 px) - the browser tab; a rounded tile, like the header's;
- `icons/Icon-192.png`, `icons/Icon-512.png` - the installed app's icon, the
  same rounded tile on transparency;
- `icons/Icon-maskable-192.png`, `icons/Icon-maskable-512.png` - full-bleed
  blue with the cap inside the safe middle, for launchers that crop the icon
  to their own shape.
"""

from pathlib import Path

from PIL import Image, ImageDraw

WEB = Path(__file__).resolve().parent.parent / "frontend" / "web"
BLUE = (0x25, 0x63, 0xEB, 255)
WHITE = (255, 255, 255, 255)
SHADE = (0xDB, 0xEA, 0xFE, 255)
AMBER = (0xF5, 0x9E, 0x0B, 255)

SUPERSAMPLE = 8


def cap(draw: ImageDraw.ImageDraw, size: int, scale: float) -> None:
    """The mortarboard on a 100 x 100 grid, shrunk about the middle by
    [scale] (1 fills a tile; a maskable icon keeps it inside the safe zone)."""

    def p(x: float, y: float) -> tuple[float, float]:
        return (
            (50 + (x - 50) * scale) * size / 100,
            (50 + (y - 50) * scale) * size / 100,
        )

    # The cap the board sits on, a shade darker so the two read apart.
    draw.polygon([p(30, 50), p(70, 50), p(70, 64), p(50, 72), p(30, 64)], fill=SHADE)
    # The board itself.
    draw.polygon([p(50, 26), p(86, 42), p(50, 58), p(14, 42)], fill=WHITE)
    # The tassel: a cord from the middle of the board's right edge, and its end.
    draw.line([p(78, 46), p(78, 62)], fill=AMBER, width=max(1, round(3.2 * scale * size / 100)))
    r = 4.2 * scale * size / 100
    cx, cy = p(78, 64)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=AMBER)


def render(px: int, *, maskable: bool) -> Image.Image:
    size = px * SUPERSAMPLE
    image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(image)

    if maskable:
        # Full bleed: the launcher cuts its own shape out of this.
        draw.rectangle([0, 0, size, size], fill=BLUE)
        cap(draw, size, 0.7)
    else:
        # The header's tile: rounded corners, about a quarter of the side.
        draw.rounded_rectangle([0, 0, size - 1, size - 1], radius=size * 0.24, fill=BLUE)
        cap(draw, size, 1.0)

    return image.resize((px, px), Image.LANCZOS)


def main() -> None:
    outputs = {
        WEB / "favicon.png": render(64, maskable=False),
        WEB / "icons" / "Icon-192.png": render(192, maskable=False),
        WEB / "icons" / "Icon-512.png": render(512, maskable=False),
        WEB / "icons" / "Icon-maskable-192.png": render(192, maskable=True),
        WEB / "icons" / "Icon-maskable-512.png": render(512, maskable=True),
    }

    for path, image in outputs.items():
        image.save(path, optimize=True)
        print(f"wrote {path.relative_to(WEB.parent.parent)} ({image.width} px)")


if __name__ == "__main__":
    main()

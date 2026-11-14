"""Draws the public website's favicons and logo in the Warm Editorial design
(2026-11-14): a white mortarboard on a rose-to-coral circle - the mark beside
the name in the website's header and footer.

    python scripts/site_icon.py

Writes into backend-python/school/public_site_assets/, from where every
build of the website copies them to the site's root:
- `favicon.ico` (16, 32, 48 px) and `favicon-48.png` - the browser tab, and
  the size Google shows in search results (a square multiple of 48 px);
- `favicon.png` (64 px) and `favicon-192.png` - larger tabs and shortcuts;
- `apple-touch-icon.png` (180 px) - a phone's home screen, full bleed,
  because iOS rounds the corners itself;
- `logo.png` (512 px) - the organisation's logo in structured data.

Drawn at 8x and scaled down for smooth edges, like scripts/web_icon.py.
"""

from pathlib import Path

from PIL import Image, ImageDraw

ASSETS = Path(__file__).resolve().parent.parent / "backend-python" / "school" / "public_site_assets"
ROSE = (0xB2, 0x46, 0x67)
CORAL = (0xE8, 0x91, 0x6F)
WHITE = (255, 255, 255, 255)
SHADE = (0xFB, 0xE4, 0xE8, 255)
GOLD = (0xFF, 0xE0, 0xAA, 255)

SUPERSAMPLE = 8


def gradient(size: int) -> Image.Image:
    """Rose at the top left to coral at the bottom right, like the header's mark."""
    image = Image.new("RGBA", (size, size))
    pixels = image.load()
    for y in range(size):
        for x in range(size):
            t = (x + y) / (2 * (size - 1))
            pixels[x, y] = tuple(round(a + (b - a) * t) for a, b in zip(ROSE, CORAL)) + (255,)
    return image


def cap(draw: ImageDraw.ImageDraw, size: int, scale: float) -> None:
    """The mortarboard on a 100 x 100 grid, shrunk about the middle by [scale]."""

    def p(x: float, y: float) -> tuple[float, float]:
        return ((50 + (x - 50) * scale) * size / 100, (50 + (y - 50) * scale) * size / 100)

    draw.polygon([p(30, 50), p(70, 50), p(70, 64), p(50, 72), p(30, 64)], fill=SHADE)
    draw.polygon([p(50, 26), p(86, 42), p(50, 58), p(14, 42)], fill=WHITE)
    draw.line([p(78, 46), p(78, 62)], fill=GOLD, width=max(1, round(3.2 * scale * size / 100)))
    r = 4.2 * scale * size / 100
    cx, cy = p(78, 64)
    draw.ellipse([cx - r, cy - r, cx + r, cy + r], fill=GOLD)


def render(px: int, *, full_bleed: bool) -> Image.Image:
    size = px * SUPERSAMPLE
    ground = gradient(px).resize((size, size), Image.BILINEAR)

    if full_bleed:
        image = ground
        draw = ImageDraw.Draw(image)
        cap(draw, size, 0.72)
    else:
        # The circle: the gradient seen through a round mask.
        image = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        mask = Image.new("L", (size, size), 0)
        ImageDraw.Draw(mask).ellipse([0, 0, size - 1, size - 1], fill=255)
        image.paste(ground, (0, 0), mask)
        draw = ImageDraw.Draw(image)
        cap(draw, size, 0.9)

    return image.resize((px, px), Image.LANCZOS)


def main() -> None:
    outputs = {
        "favicon-48.png": render(48, full_bleed=False),
        "favicon.png": render(64, full_bleed=False),
        "favicon-192.png": render(192, full_bleed=False),
        "apple-touch-icon.png": render(180, full_bleed=True),
        "logo.png": render(512, full_bleed=False),
    }
    for name, image in outputs.items():
        image.save(ASSETS / name, optimize=True)
        print(f"wrote {name} ({image.width} px)")

    render(48, full_bleed=False).save(ASSETS / "favicon.ico", sizes=[(16, 16), (32, 32), (48, 48)])
    print("wrote favicon.ico (16, 32, 48 px)")


if __name__ == "__main__":
    main()

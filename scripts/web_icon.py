"""Draws the web app's favicon and install icons.

    python scripts/web_icon.py

The website's mark (Warm Editorial, 2026-11-14): a white mortarboard on a
rose-to-coral circle, drawn by the same code as the website's favicon
(scripts/site_icon.py), so the tab looks the same on school365ai.com and on
school365ai.com/app/.

Writes into frontend/web/:
- `favicon.png` (64 px) - the browser tab;
- `icons/Icon-192.png`, `icons/Icon-512.png` - the installed app's icon, the
  circle on transparency;
- `icons/Icon-maskable-192.png`, `icons/Icon-maskable-512.png` - the
  gradient full bleed with the cap inside the safe middle, for launchers that
  crop the icon to their own shape.

After running it, raise the `?v=` on the favicon and icon links in
frontend/web/index.html, so browsers fetch the new files.
"""

from pathlib import Path

from PIL import Image, ImageDraw

from site_icon import SUPERSAMPLE, cap, gradient, render

WEB = Path(__file__).resolve().parent.parent / "frontend" / "web"


def maskable(px: int) -> Image.Image:
    """Full bleed, the cap small enough for the 80% safe zone."""
    size = px * SUPERSAMPLE
    image = gradient(px).resize((size, size), Image.BILINEAR)
    cap(ImageDraw.Draw(image), size, 0.6)
    return image.resize((px, px), Image.LANCZOS)


def main() -> None:
    outputs = {
        WEB / "favicon.png": render(64, full_bleed=False),
        WEB / "icons" / "Icon-192.png": render(192, full_bleed=False),
        WEB / "icons" / "Icon-512.png": render(512, full_bleed=False),
        WEB / "icons" / "Icon-maskable-192.png": maskable(192),
        WEB / "icons" / "Icon-maskable-512.png": maskable(512),
    }
    for path, image in outputs.items():
        image.save(path, optimize=True)
        print(f"wrote {path.relative_to(WEB)} ({image.width} px)")


if __name__ == "__main__":
    main()

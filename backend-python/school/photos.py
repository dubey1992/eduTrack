"""Profile photos: checking an upload, storing it, and reading it back
(docs/profile.md).

**An upload is decoded, never trusted.** The file's name and the type the
browser claims both come from the client, so neither decides anything. The
bytes are opened with Pillow; only a real JPEG or PNG is accepted, and it is
then re-encoded - scaled to at most 512 pixels on its longer side and saved
fresh. Re-encoding is what makes the stored file safe to serve: whatever
rode along in the upload (EXIF with GPS co-ordinates, a script appended
after the image data, a file that is two formats at once) is not copied
into the new one.

**Stored through Django's storage API**, under a random name in
`profile-photos/`. Local disk today (`MEDIA_ROOT`, outside anything a web
server serves); moving to S3 later is a settings change, not a code change.
The file is only ever read back through the authenticated photo endpoint.
"""

from __future__ import annotations

import io
import uuid

from django.core.files.base import ContentFile
from django.core.files.storage import default_storage
from PIL import Image, ImageOps, UnidentifiedImageError

MAX_BYTES = 2 * 1024 * 1024
MAX_SIDE = 512
FOLDER = "profile-photos"

# Pillow format name -> (content type, extension).
ACCEPTED = {"JPEG": ("image/jpeg", "jpg"), "PNG": ("image/png", "png")}

# A decompression bomb - a tiny file that unpacks to billions of pixels -
# is refused rather than decoded. 40 megapixels is far past any phone camera.
Image.MAX_IMAGE_PIXELS = 40_000_000


class PhotoRejected(Exception):
    """The upload is not a photo we will keep. The message is for the person."""


def prepare(
    upload,
    *,
    max_side: int = MAX_SIDE,
    max_bytes: int = MAX_BYTES,
    noun: str = "photo",
    aspect: tuple[int, int] | None = None,
) -> tuple[bytes, str]:
    """The upload, checked and re-encoded: (bytes, extension).

    [max_side] and [max_bytes] are a profile photo's unless given; a blog
    post's cover is larger (school/views/site_pages.py). [noun] names it in
    the refusals. [aspect], as (width, height), first cuts the picture to
    that shape around its centre - a student's photo is cut to 3:4, the
    passport shape of the box printed on admit cards and report cards
    (docs/student-photos.md, D2). Raises PhotoRejected with a sentence the
    person can act on.
    """
    if upload is None:
        raise PhotoRejected(f"Choose {_article(noun)} {noun} to upload.")

    if upload.size > max_bytes:
        raise PhotoRejected(f"The {noun} must be {max_bytes // (1024 * 1024)} MB or smaller.")

    raw = upload.read()

    try:
        with Image.open(io.BytesIO(raw)) as probe:
            probe.verify()

        # verify() leaves the image unusable, so it is opened again to decode.
        image = Image.open(io.BytesIO(raw))
        image.load()
    except (UnidentifiedImageError, OSError, SyntaxError, Image.DecompressionBombError):
        raise PhotoRejected(f"The {noun} must be a JPEG or PNG image.")

    if image.format not in ACCEPTED:
        raise PhotoRejected(f"The {noun} must be a JPEG or PNG image.")

    _content_type, extension = ACCEPTED[image.format]

    # A phone photo is often stored sideways with a note saying which way
    # is up; that note is about to be dropped, so the turn is applied first.
    image = ImageOps.exif_transpose(image)

    if aspect is not None:
        image = centre_crop(image, aspect)

    image.thumbnail((max_side, max_side))

    out = io.BytesIO()

    if extension == "jpg":
        image.convert("RGB").save(out, format="JPEG", quality=85, optimize=True)
    else:
        image.save(out, format="PNG", optimize=True)

    return out.getvalue(), extension


def centre_crop(image: Image.Image, aspect: tuple[int, int]) -> Image.Image:
    """The largest [aspect]-shaped part of [image] around its centre."""
    width, height = image.size
    ratio_w, ratio_h = aspect

    if width * ratio_h > height * ratio_w:
        # Too wide: keep the full height, trim the sides.
        new_width = max(1, round(height * ratio_w / ratio_h))
        left = (width - new_width) // 2
        return image.crop((left, 0, left + new_width, height))

    # Too tall (or already right): keep the full width, trim top and bottom.
    new_height = max(1, round(width * ratio_h / ratio_w))
    top = (height - new_height) // 2
    return image.crop((0, top, width, top + new_height))


def store(data: bytes, extension: str, folder: str = FOLDER) -> str:
    """Saves the prepared bytes under a fresh random name; returns the path."""
    return default_storage.save(f"{folder}/{uuid.uuid4().hex}.{extension}", ContentFile(data))


def _article(noun: str) -> str:
    return "an" if noun[:1] in "aeiou" else "a"


def remove(path: str | None) -> None:
    """Deletes a stored photo. A file that is already gone is not an error:
    the point is that it should not be there, and it is not."""
    if path and default_storage.exists(path):
        default_storage.delete(path)


def read(path: str) -> tuple[bytes, str] | None:
    """The stored bytes and their content type, or None when the file is
    missing - a row pointing at nothing is shown as "no photo"."""
    if not path or not default_storage.exists(path):
        return None

    with default_storage.open(path, "rb") as handle:
        data = handle.read()

    content_type = "image/png" if path.endswith(".png") else "image/jpeg"

    return data, content_type

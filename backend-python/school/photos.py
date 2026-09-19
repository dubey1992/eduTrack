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


def prepare(upload) -> tuple[bytes, str]:
    """The upload, checked and re-encoded: (bytes, extension).

    Raises PhotoRejected with a sentence the person can act on.
    """
    if upload is None:
        raise PhotoRejected("Choose a photo to upload.")

    if upload.size > MAX_BYTES:
        raise PhotoRejected("The photo must be 2 MB or smaller.")

    raw = upload.read()

    try:
        with Image.open(io.BytesIO(raw)) as probe:
            probe.verify()

        # verify() leaves the image unusable, so it is opened again to decode.
        image = Image.open(io.BytesIO(raw))
        image.load()
    except (UnidentifiedImageError, OSError, SyntaxError, Image.DecompressionBombError):
        raise PhotoRejected("The photo must be a JPEG or PNG image.")

    if image.format not in ACCEPTED:
        raise PhotoRejected("The photo must be a JPEG or PNG image.")

    _content_type, extension = ACCEPTED[image.format]

    # A phone photo is often stored sideways with a note saying which way
    # is up; that note is about to be dropped, so the turn is applied first.
    image = ImageOps.exif_transpose(image)
    image.thumbnail((MAX_SIDE, MAX_SIDE))

    out = io.BytesIO()

    if extension == "jpg":
        image.convert("RGB").save(out, format="JPEG", quality=85, optimize=True)
    else:
        image.save(out, format="PNG", optimize=True)

    return out.getvalue(), extension


def store(data: bytes, extension: str) -> str:
    """Saves the prepared bytes under a fresh random name; returns the path."""
    return default_storage.save(f"{FOLDER}/{uuid.uuid4().hex}.{extension}", ContentFile(data))


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

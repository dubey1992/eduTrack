"""The endpoint the fingerprint readers talk to (docs/biometric.md, B4).

**This is the one part of the product whose URLs are not ours.** The firmware
appends its own path - `/iclock/cdata`, `/iclock/getrequest` - so these sit at
the domain root rather than under `/api/v1/`, and they answer plain text
rather than the JSON envelope. Both are deliberate exceptions, and both exist
because a device cannot be asked to do anything else.

**Written against the common ZKTeco push dialect**, which is what the boxes
schools buy tend to speak, and liberally: tabs or commas, seconds optional,
unknown tables acknowledged and ignored. The raw line of every punch is kept
(`biometric_punches.raw`), so when a real device turns out to differ, the
evidence for fixing it is already in the database rather than lost in a 400.

**A serial number is not a credential.** It is printed on the box and sent in
the clear, so anybody who learns one can post punches for that school. What
limits the damage, in order of how much work each does:

- **A punch writes times, and marks an unmarked working day Present** -
  the rule the school asked for (docs/biometric.md) - but never Absent,
  never Late, and never over a mark a person made. So a forgery can give
  somebody a day they were not in, which is exactly why a device should
  have a `push_key` wherever its firmware can send one.
- **An unknown serial is refused**, and the attempt is audited - once per
  sender per ten minutes, so somebody guessing serials cannot fill the
  audit log. A device is registered by a person before it is trusted.
- **A shared secret where the firmware can send one** (`push_key`). Null
  means none is required, which is the only workable answer for older boxes.
- **A rate limit per serial**, so a leaked serial cannot be used to flood.

What this does *not* claim to be is authentication. Saying so plainly is the
point: the alternative - pretending the serial proves anything - is how an
endpoint like this becomes the weak point of an otherwise careful system.
"""

from __future__ import annotations

import datetime as dt
import hmac

from django.core.cache import cache

from django.http import HttpResponse
from django.utils import timezone
from rest_framework.decorators import api_view, permission_classes, throttle_classes

from .. import audit, modules, punches
from ..models import BiometricDevice
from ..throttling import DevicePushThrottle

# What the firmware sends as a field separator. Tab is the documented one;
# comma appears in the wild, and accepting both costs nothing.
SEPARATORS = ("\t", ",")

# The device's own stamp, which is wall clock at the school and carries no
# zone - the same fact the CSV upload deals with, handled the same way.
DEVICE_FORMATS = ("%Y-%m-%d %H:%M:%S", "%Y-%m-%d %H:%M")

# How long one sender's unknown-serial attempts share a single audit entry.
UNKNOWN_AUDIT_WINDOW_S = 600


def _text(body: str, status: int = 200) -> HttpResponse:
    """Plain text, which is the only thing this firmware reads. A JSON
    envelope here would be answered with a parse error and a retry loop."""
    return HttpResponse(body, status=status, content_type="text/plain; charset=utf-8")


def _device(request) -> BiometricDevice | None:
    """The registered device this request claims to be, or None.

    None covers three cases that are one case to the caller: no serial, a
    serial nobody registered, and a wrong key. They are deliberately not
    told apart in the response - a probe learns nothing from the difference.
    """
    serial = (request.GET.get("SN") or request.GET.get("sn") or "").strip()

    if not serial:
        return None

    device = BiometricDevice.objects.filter(serial_number=serial).first()

    if device is None:
        # Worth an audit entry rather than a silent 401: a device somebody
        # installed and forgot to register looks exactly like this, and so
        # does somebody guessing serials. One entry per sender per window:
        # the throttle is per serial, so a guesser rotating serials would
        # otherwise write a row per request.
        if cache.add(f"iclock-unknown:{audit.ip_of(request)}", True, timeout=UNKNOWN_AUDIT_WINDOW_S):
            audit.record(
                actor=None,
                action="biometric.unknown_device",
                module="staff_attendance",
                entity_type="biometric_device",
                entity_id=None,
                school_id=None,
                new={"serial_number": serial[:64]},
                request=request,
            )

        return None

    # Compared in constant time, so the answer's timing says nothing about
    # how much of a guessed key was right.
    if device.push_key and not hmac.compare_digest(
        device.push_key.encode(), (request.GET.get("key") or "").strip().encode()
    ):
        return None

    # A school that has switched biometric off is not collecting punches,
    # and a device still pointed at us must not keep filing them.
    if not modules.is_enabled(device.school_id, "biometric"):
        return None

    return device


def _seen(device: BiometricDevice) -> None:
    """Every contact, not just a punch.

    A device that handshakes every minute and has sent no punches since
    Tuesday is a different fault from one that has gone quiet altogether,
    and only this column tells them apart.
    """
    BiometricDevice.objects.filter(pk=device.pk).update(last_seen_at=timezone.now())


@api_view(["GET", "POST"])
@permission_classes([])
@throttle_classes([DevicePushThrottle])
def cdata(request) -> HttpResponse:
    """The handshake, and the punches.

    One URL doing two jobs because the firmware uses one URL for both: a GET
    asks what the server wants, a POST delivers a table of records.
    """
    device = _device(request)

    if device is None:
        return _text("Unauthorized", status=401)

    _seen(device)

    if request.method == "GET":
        return _text(_options(device))

    table = (request.GET.get("table") or "").upper()

    if table and table != "ATTLOG":
        # Operation logs, enrolment changes, photographs. Acknowledged so the
        # device stops resending, and dropped: none of them is attendance,
        # and storing what we will not read is a liability, not a feature.
        return _text("OK")

    return _text(f"OK: {_record(device, request.body)}")


def _options(device: BiometricDevice) -> str:
    """What the device asks for before it will send anything.

    Kept to the few lines the firmware actually needs. `Stamp` is how it
    decides what it has already sent, and 0 asks for everything it holds -
    which is what makes a newly registered device deliver its backlog
    instead of only what happens next.
    """
    return "\n".join(
        [
            f"GET OPTION FROM: {device.serial_number}",
            "Stamp=0",
            "OpStamp=0",
            # Seconds between uploads, and between retries after a failure.
            # Deliberately unhurried: these are attendance times, not a live
            # feed, and a shared host does not want a box polling every
            # second.
            "Delay=30",
            "ErrorDelay=60",
            "TransTimes=00:00;12:00",
            "TransInterval=1",
            # Attendance logs on, everything else off - the same decision as
            # dropping the other tables above, said in the device's own
            # dialect so it never sends them in the first place.
            "TransFlag=100000000000",
            "Realtime=1",
            "Encrypt=0",
            "",
        ]
    )


def _record(device: BiometricDevice, body: bytes) -> int:
    """One batch of punches, as the device spells them.

    Returns how many were new, which is what the firmware wants back. A line
    it cannot parse is skipped rather than failing the batch: the rest of
    the upload is real attendance, and a box that gets a 500 will resend the
    same unparseable line for ever.
    """
    rows = []

    for line in body.decode("utf-8", errors="replace").splitlines():
        row = _read_line(line)

        if row is not None:
            rows.append(row)

    if not rows:
        return 0

    outcome = punches.record(device.school_id, rows, source=punches.DEVICE, device=device)

    audit.record(
        actor=None,
        action="biometric.punches_pushed",
        module="staff_attendance",
        entity_type="biometric_device",
        entity_id=device.pk,
        school_id=device.school_id,
        new={
            "accepted": outcome.accepted,
            "duplicate": outcome.duplicate,
            "register_marked": outcome.register_marked,
            "register_filled": outcome.register_filled,
        },
        request=None,
    )

    return outcome.accepted


def _read_line(line: str) -> dict | None:
    """`user_id<TAB>2026-10-21 09:02:17<TAB>status<TAB>verify...`

    Only the first two fields are ours. The rest - verify mode, work code,
    which finger - say nothing about whether somebody was at school, and
    asking a school to care about them would be asking for nothing.
    """
    if not line.strip():
        return None

    parts = None

    for separator in SEPARATORS:
        if separator in line:
            parts = [part.strip() for part in line.split(separator)]
            break

    if parts is None or len(parts) < 2:
        return None

    who, when = parts[0], parts[1]

    if not who or len(who) > 32:
        return None

    moment = _read_time(when)

    if moment is None:
        return None

    return {"biometric_user_id": who, "punched_at": moment, "raw": line.strip()[:255]}


def _read_time(value: str) -> dt.datetime | None:
    """Naive on purpose: the zone belongs to the school, not to the box."""
    for shape in DEVICE_FORMATS:
        try:
            return dt.datetime.strptime(value, shape)
        except ValueError:
            continue

    return None


@api_view(["GET", "POST"])
@permission_classes([])
@throttle_classes([DevicePushThrottle])
def getrequest(request) -> HttpResponse:
    """"Is there anything for me to do?" - no.

    This product never sends a device a command: it does not enrol fingers,
    set the clock, or open a door, and every one of those would be a way for
    a compromised server to reach into a school. The endpoint exists because
    the firmware polls it and treats a 404 as a fault.
    """
    device = _device(request)

    if device is None:
        return _text("Unauthorized", status=401)

    _seen(device)

    return _text("OK")


@api_view(["GET", "POST"])
@permission_classes([])
@throttle_classes([DevicePushThrottle])
def devicecmd(request) -> HttpResponse:
    """Where a device reports what it did with a command. We send none, so
    there is nothing to reconcile - acknowledged and dropped."""
    device = _device(request)

    if device is None:
        return _text("Unauthorized", status=401)

    _seen(device)

    return _text("OK")

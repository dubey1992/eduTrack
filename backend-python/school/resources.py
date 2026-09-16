"""What a record looks like on the wire.

The Python half of App/Http/Resources. Every key here is read by name in the
Flutter apps, so this file is the contract in the most literal sense: renaming
`first_name`, or sending an id as a string, breaks a client that rule 1 of the
migration says must not be touched.

Plain functions returning dicts, not DRF serializers. Two reasons. Laravel's
resources are exactly this - a method returning an array - so a reviewer can
put the two side by side and see that they agree. And `whenLoaded` has no DRF
equivalent: it omits a key rather than sending null, and reproducing "the key
is absent" through a serializer field would take more machinery than the thing
it is reproducing.
"""

from __future__ import annotations

from .clock import SchoolClock
from .fields import as_utc
from .models import School, Student, StudentTransportAssignment, User
from .scope import SchoolScope


def timestamp(value) -> str | None:
    """An instant in the form Eloquent's JSON serialization produces -
    `2026-09-16T10:23:45.000000Z`.

    Six digits of fractional seconds and a literal Z, always, because that is
    what the client has been parsing since the first release.

    Through `as_utc` rather than a bare `.astimezone()`: a naive datetime out
    of a `timestamp without time zone` column means UTC here, and Python's
    default reading of a naive value is the machine's local zone. See
    school/fields.py - this is the second line of defence, the field being the
    first.
    """
    if value is None:
        return None

    return as_utc(value).strftime("%Y-%m-%dT%H:%M:%S.%f") + "Z"


def academic_year_resource(year) -> dict:
    body = {
        "id": year.id,
        "school_id": year.school_id,
        "name": year.name,
        # Dates, not instants: `2026-04-01` is the same day everywhere, and
        # rendering it through a timezone would move it.
        "start_date": year.start_date.isoformat(),
        "end_date": year.end_date.isoformat(),
        "is_current": year.is_current,
        "created_at": timestamp(year.created_at),
    }

    if loaded(year, "school"):
        body["school_name"] = year.school.name

    return body


def school_resource(school: School, branch_count: int | None = None) -> dict:
    """A school, or a branch of one.

    `branch_count` is passed in rather than read off the instance: it comes
    from an annotation on the list query, and a resource that fetched it
    itself would fire a query per row.
    """
    body = {
        "id": school.id,
        "name": school.name,
        # Where this school sits in its group. Null for a standalone school,
        # which is what most are. See docs/branches.md.
        "parent_school_id": school.parent_school_id,
        "registration_number": school.registration_number,
        "email": school.email,
        "phone": school.phone,
        "address": school.address,
        "city": school.city,
        "state": school.state,
        "country": school.country,
        "postal_code": school.postal_code,
        # Strings, not floats. `decimal(10,7)` through a float loses the
        # seventh place, and Laravel's `decimal:7` cast sends a string too.
        "latitude": None if school.latitude is None else str(school.latitude),
        "longitude": None if school.longitude is None else str(school.longitude),
        "currency_code": school.currency_code,
        "timezone": school.timezone,
        "logo_url": school.logo_url,
        "status": school.status,
        "created_at": timestamp(school.created_at),
    }

    if loaded(school, "parent_school"):
        body["parent_school_name"] = school.parent_school.name if school.parent_school else None

    if branch_count is not None:
        body["branch_count"] = branch_count

    return body


def user_resource(user: User, viewer: User | None = None) -> dict:
    """The session user - what login returns and what /me answers.

    `viewer` is whoever is reading. It decides one field (see
    `manages_branches` below) and is passed explicitly rather than pulled off
    a request, because at login there is no authenticated request yet: the
    token was issued a line earlier.
    """
    # Reads the already-loaded school where there is one, so a paginated user
    # list does not fire a query per row.
    clock = SchoolClock.for_user(user)

    body = {
        "id": user.id,
        "first_name": user.first_name,
        "last_name": user.last_name,
        "name": user.name,
        "email": user.email,
        "mobile": user.mobile,
        "role": user.role,
        "is_sub_admin": user.is_sub_admin,
        "status": user.status,
        "school_id": user.school_id,
        # True for an account created by a bulk import, which was given a
        # generated password: the client keeps it on the change-password
        # screen until it chooses one of its own.
        "must_change_password": user.must_change_password,
        "timezone": clock.timezone(),
        # The session's clock. The client measures every date it shows or
        # defaults to against these two, never against the browser's own
        # timezone. A Super Admin belongs to no school and gets the platform's
        # zone.
        "current_time": clock.now_iso8601(),
    }

    if "school" in user._state.fields_cache:
        body["school_name"] = user.school.name if user.school else None

    # Whether "my school" is ambiguous for this account, so the client knows
    # to ask which branch a record belongs to. True for an admin of a school
    # in a group, false for a standalone one - which is why the client cannot
    # work it out from the role alone.
    #
    # Only ever computed for the signed-in user reading their own session: it
    # costs a query, and a paginated user list would pay it per row for
    # something no row needs.
    if viewer is not None and viewer.id == user.id:
        body["manages_branches"] = SchoolScope.for_actor(user).covers_a_group()

    return body


def loaded(instance, name: str) -> bool:
    """Has this relation already been fetched?

    The Python answer to Eloquent's `relationLoaded()`, and it decides whether
    a key appears at all - `whenLoaded` omits a field rather than sending null,
    so getting this wrong changes the shape rather than the value. Asked
    through the field's own `is_cached` rather than by poking at the instance,
    because that is the supported way and touching the attribute would silently
    fire the query this is trying to avoid.
    """
    return instance._meta.get_field(name).is_cached(instance)


def student_resource(student: Student) -> dict:
    section = student.class_section

    body = {
        "id": student.id,
        "school_id": student.school_id,
        "class_section_id": student.class_section_id,
        "class_section_name": (
            f"{section.school_class.name} {section.name}".strip()
            if section is not None and loaded(section, "school_class")
            else None
        ),
        "admission_number": student.admission_number,
        "first_name": student.first_name,
        "last_name": student.last_name,
        "name": student.name,
        "roll_number": student.roll_number,
        "guardian_name": student.guardian_name,
        "guardian_mobile": student.guardian_mobile,
        "address": student.address,
        "status": student.status,
        "created_at": timestamp(student.created_at),
    }

    if loaded(student, "school"):
        body["school_name"] = student.school.name if student.school else None

    if loaded(student, "studenttransportassignment"):
        body["transport"] = transport_resource(assignment_of(student))

    return body


def assignment_of(student: Student):
    """The student's transport assignment, or None.

    A reverse one-to-one raises rather than returning None when there is no
    matching row, even after select_related has established that there isn't
    one. Django models a missing one-to-one as an error; Laravel models it as
    null, and null is what the client is promised.
    """
    try:
        return student.studenttransportassignment
    except StudentTransportAssignment.DoesNotExist:
        return None


def transport_resource(assignment) -> dict | None:
    """The student's current bus route and stop, or null when they do not use
    school transport.

    Transport is M11's work, but this key is part of the student's shape and
    Laravel's StudentController eager-loads the relation - so Laravel always
    sends `transport`, as null for most students. Omitting the key here would
    have been a difference the Flutter client happens to survive, since it
    reads a missing key and an explicit null the same way. Surviving a
    difference is not the same as not having one.
    """
    if assignment is None:
        return None

    route = assignment.route

    return {
        "route_id": assignment.route_id,
        "route_name": route.name,
        "route_label": route_label(route),
        "vehicle_name": route.vehicle.name if route.vehicle_id else None,
        "stop_id": assignment.transport_stop_id,
        "stop_name": assignment.transport_stop.name,
    }


def route_label(route) -> str:
    """"Bus 04 - Green Park" - the vehicle and the route, as a driver would
    say it. Ported from TransportRoute::label()."""
    vehicle = route.vehicle.name if route.vehicle_id else None

    return f"{vehicle} - {route.name}" if vehicle else route.name

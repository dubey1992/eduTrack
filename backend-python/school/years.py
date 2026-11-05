"""The academic year a list is asked for (decided 2026-11-05).

The top bar's year switch sends `academic_year_id`; every list that follows
it reads it here, so a year of another school is refused the same way
everywhere - a 422, never quietly ignored.
"""

from __future__ import annotations

from rest_framework import serializers

from .models import AcademicYear
from .requests import php_int
from .scope import SchoolScope
from .validation import selected_is_invalid


def year_in_view(request) -> AcademicYear | None:
    """The year asked for, or None when none is - a year of a school the
    actor answers for, or a 422."""
    raw = request.query_params.get("academic_year_id")
    if raw in (None, ""):
        return None

    year = AcademicYear.objects.filter(pk=php_int(raw)).first()
    if year is None or not SchoolScope.for_actor(request.user).allows(year.school_id):
        raise serializers.ValidationError({"academic_year_id": [selected_is_invalid("academic_year_id")]})

    return year

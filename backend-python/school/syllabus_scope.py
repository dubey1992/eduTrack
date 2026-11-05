"""Which syllabus topics belong to which class (decided 2026-11-05).

A topic is written for a class - Computer Science for Playgroup is not
Computer Science for Class 9 - and every section of that class shares it. It
is filed against the class *level* (Playgroup -3 ... Class 12), not a class
row: classes are made afresh each academic year, and a syllabus carries over.

A topic with no level was written before this existed. It still applies to
every class until somebody gives it one, so nobody's syllabus vanished when
the rule arrived.
"""

from __future__ import annotations

from django.db.models import Count, Q

from . import class_levels
from .models import ClassSection, SyllabusTopic

ALL_CLASSES = "All classes"


def for_level(topics, level: int | None):
    """The topics a class at `level` follows: its own, and those for every
    class. No level asked for is no narrowing at all."""
    if level is None:
        return topics

    return topics.filter(Q(class_level=level) | Q(class_level__isnull=True))


def applies_to(topic: SyllabusTopic, level: int | None) -> bool:
    return topic.class_level is None or level is None or topic.class_level == level


def level_of_section(section_id) -> int | None:
    return ClassSection.objects.filter(pk=section_id).values_list("school_class__level", flat=True).first()


def levels_of_sections(section_ids) -> dict[int, int]:
    return dict(ClassSection.objects.filter(pk__in=section_ids).values_list("id", "school_class__level"))


def counts(subject_ids) -> dict[tuple[int, int | None], int]:
    """How many topics each subject has for each level, None standing for
    the topics every class follows - one query, whatever the size."""
    return {
        (row["subject_id"], row["class_level"]): row["n"]
        for row in SyllabusTopic.objects.filter(subject_id__in=subject_ids)
        .values("subject_id", "class_level")
        .annotate(n=Count("id"))
    }


def total_for(per_level: dict[tuple[int, int | None], int], subject_id: int, level: int | None) -> int:
    """A class's topics in a subject from [counts]: its level's, plus the
    ones for every class. With no level, every topic of the subject."""
    if level is None:
        return sum(n for (subject, _), n in per_level.items() if subject == subject_id)

    return per_level.get((subject_id, level), 0) + per_level.get((subject_id, None), 0)


def level_name(level: int | None) -> str:
    """"Playgroup", "Class 5" - or "All classes" for a topic with none."""
    if level is None:
        return ALL_CLASSES

    return next((name for name, value in class_levels.STANDARD if value == level), f"Level {level}")

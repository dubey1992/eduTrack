"""Which year of school a class is, from its name (docs/onboarding.md).

A class's `level` orders it - Nursery before LKG before Class 1 - and is what
promotion steps up by one. Nobody should have to know that: a class called
"LKG" or "Class 7" says which year it is, so the level is worked out from the
name, and a school can set up Nursery to Class 10 in one step.

Levels below 0 are the pre-primary years, so that schools which already use 0
for their first year before Class 1 keep their order:

    Playgroup -3, Nursery -2, LKG -1, UKG 0, Class 1 ... Class 12 = 1 ... 12
"""

from __future__ import annotations

import re

LOWEST = -3
HIGHEST = 12

# The standard classes Quick setup offers, in order. Named the way the user
# chose (2026-10-31): "Class 1", "Class 2" ...
STANDARD: tuple[tuple[str, int], ...] = (
    ("Playgroup", -3),
    ("Nursery", -2),
    ("LKG", -1),
    ("UKG", 0),
    *((f"Class {n}", n) for n in range(1, HIGHEST + 1)),
)

# Ticked when Quick setup opens: Nursery to Class 10.
DEFAULT_SELECTION = tuple(name for name, level in STANDARD if -2 <= level <= 10)

# Pre-primary names schools use, lower-cased, without spaces or dots.
PRE_PRIMARY = {
    "playgroup": -3, "playschool": -3, "pg": -3, "prenursery": -3, "toddler": -3,
    "nursery": -2, "nur": -2,
    "lkg": -1, "kg1": -1, "lowerkg": -1, "lowerkindergarten": -1, "junkg": -1, "juniorkg": -1, "prep1": -1,
    "ukg": 0, "kg2": 0, "upperkg": 0, "upperkindergarten": 0, "senkg": 0, "seniorkg": 0, "kg": 0,
    "kindergarten": 0, "reception": 0, "prep": 0, "prep2": 0,
}

ROMAN = {
    "i": 1, "ii": 2, "iii": 3, "iv": 4, "v": 5, "vi": 6, "vii": 7, "viii": 8, "ix": 9, "x": 10, "xi": 11, "xii": 12,
}

# "Class 7", "Grade 7", "Std. 7", "Standard VII", "Year 7", "7th", "7".
NUMBERED = re.compile(
    r"^(?:(?:class|grade|std|standard|year|yr)\s*)?(?P<number>\d{1,2}|[ivx]{1,4})(?:st|nd|rd|th)?$"
)


def infer(name: str | None) -> int | None:
    """The level a class's name says, or None when it says nothing a school
    would mean by it - and then the person picks the level themselves."""
    if not name:
        return None

    text = " ".join(name.lower().replace(".", " ").replace("-", " ").split())
    squeezed = text.replace(" ", "")

    if squeezed in PRE_PRIMARY:
        return PRE_PRIMARY[squeezed]

    match = NUMBERED.match(text)

    if match is None:
        return None

    number = match.group("number")
    level = int(number) if number.isdigit() else ROMAN.get(number)

    return level if level is not None and 1 <= level <= HIGHEST else None

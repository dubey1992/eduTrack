"""What a mark is worth, as arithmetic (docs/assessments.md).

Pure on purpose, like insights.py: no database, no clock, no model. It is
handed marks and returns numbers, which is what lets a student's page and
the two performance reports share one set of rules instead of each carrying
its own copy - the way a figure on a report ends up disagreeing with the
same figure on the screen it came from.

Two of the rules are the product's, not arithmetic's:

- **Absent is not zero.** An absentee leaves the denominator rather than
  dragging the mean down, so a subject missed entirely has no average at
  all - not a nought.
- **Weightages count only where every test carries one.** Half a weighting
  is not a weighting.
"""

from __future__ import annotations

import decimal

CENT = decimal.Decimal("0.01")


def percentage_of(mark) -> decimal.Decimal | None:
    """One mark as a percentage, or nothing where the question does not
    arise: absent, unmarked, or a test out of nothing."""
    assessment = mark.assessment

    if mark.is_absent or mark.marks_obtained is None or not assessment.max_marks:
        return None

    return (mark.marks_obtained / assessment.max_marks * 100).quantize(CENT)


def average_of(rows: list[tuple]) -> decimal.Decimal | None:
    """The mean of (percentage, weightage) pairs.

    Weighted only when every test counted carries a weightage, and then
    normalised by the weights actually present - a term whose weightages add
    up to 80 is a school part-way through setting them, not a reason to
    divide by 100 and report everybody as failing. Mixed weightages and
    blanks fall back to a plain mean, because half a weighting is not a
    weighting.
    """
    if not rows:
        return None

    weights = [weight for _, weight in rows]

    if all(weight is not None and weight > 0 for weight in weights):
        total = sum(weights)

        return (sum(value * weight for value, weight in rows) / total).quantize(CENT)

    return (sum(value for value, _ in rows) / len(rows)).quantize(CENT)


def mean_of(values: list) -> decimal.Decimal | None:
    """An unweighted mean of figures that are already averages.

    A term's overall average weighs each subject evenly rather than each
    mark, so a subject with eight tests does not drown one with two.
    """
    kept = [value for value in values if value is not None]

    if not kept:
        return None

    return (sum(kept) / len(kept)).quantize(CENT)


def change_between(now, before) -> decimal.Decimal | None:
    if now is None or before is None:
        return None

    return (now - before).quantize(CENT)


def text(value) -> str | None:
    """A figure as the API writes it, or nothing where there is nothing.

    A string rather than a float: these are decimals, and a client that
    reads 72.5 as a double and writes it back has already lost the point.
    """
    return None if value is None else str(value)

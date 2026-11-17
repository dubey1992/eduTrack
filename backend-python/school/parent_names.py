"""A student's father's and mother's names, for printed documents
(docs/document-styles.md, decided 2026-11-17).

The student record holds one guardian name. A father or a mother is known by
name only where a Family-app parent account is linked to the student with
that relationship (school/family_accounts.py). Nothing here guesses: a
document prints "Father's Name" only when a link says father, and falls back
to the guardian name the school typed in.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ParentNames:
    father: str | None
    mother: str | None
    guardian: str | None

    def first_line(self) -> tuple[str, str | None]:
        """The one parent line a receipt has room for: the father, else the
        mother, else the guardian - with its label."""
        if self.father:
            return "Father's Name", self.father

        if self.mother:
            return "Mother's Name", self.mother

        return "Guardian Name", self.guardian


def parent_names(student) -> ParentNames:
    """On this branch the Family app's parent links do not exist yet, so a
    document always prints the guardian name the school typed in. Father's
    and mother's names arrive with the Family app (main)."""
    return ParentNames(father=None, mother=None, guardian=student.guardian_name or None)

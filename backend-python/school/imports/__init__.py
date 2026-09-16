"""Bulk upload: download a template, fill it in, send it back.

One pair of endpoints covers every kind of record, because the only thing that
differs between importing students and importing vehicles is the importer.

M8 registers students. The other four kinds - staff, subjects, vehicles,
drivers - arrive with their own modules, because each one's importer leans on
that module's create rules and porting it early would mean porting those
rules twice.
"""

from __future__ import annotations

from ..models import Student
from ..policies import StudentPolicy
from .students import StudentImporter

# Each type names the importer and the policy that already decides who may add
# one of these by hand. Importing a hundred of them is the same permission, so
# there is no separate set of import rules to keep in step.
TYPES = {
    "students": {"importer": StudentImporter, "model": Student, "policy": StudentPolicy},
}


def has(kind: str) -> bool:
    return kind in TYPES


def importer(kind: str):
    """A fresh importer each time: they cache the school's sections while they
    work, which is only ever right for one import."""
    return TYPES[kind]["importer"]()


def policy(kind: str):
    return TYPES[kind]["policy"]

"""Bulk upload: download a template, fill it in, send it back.

One pair of endpoints covers every kind of record, because the only thing that
differs between importing students and importing vehicles is the importer.

Students came with M8; staff, subjects, vehicles and drivers with M11, each
leaning on its own module's create service so an imported record is exactly
what the single-record form would have made.
"""

from __future__ import annotations

from ..models import Assessment, Driver, StaffProfile, Student, Subject, Vehicle
from ..policies import StaffProfilePolicy, StudentPolicy, SubjectPolicy, TransportMasterPolicy
from .assessments import AssessmentImporter, AssessmentImportPolicy
from .people_and_fleet import DriverImporter, StaffImporter, SubjectImporter, VehicleImporter
from .students import StudentImporter

# Each type names the importer and the policy that already decides who may add
# one of these by hand. Importing a hundred of them is the same permission, so
# there is no separate set of import rules to keep in step.
TYPES = {
    "students": {"importer": StudentImporter, "model": Student, "policy": StudentPolicy},
    "staff": {"importer": StaffImporter, "model": StaffProfile, "policy": StaffProfilePolicy},
    "subjects": {"importer": SubjectImporter, "model": Subject, "policy": SubjectPolicy},
    "vehicles": {"importer": VehicleImporter, "model": Vehicle, "policy": TransportMasterPolicy},
    "drivers": {"importer": DriverImporter, "model": Driver, "policy": TransportMasterPolicy},
    # Class tests, added 2026-09-24 (docs/assessments.md). An
    # administrator's tool, like the rest of this file.
    "assessments": {"importer": AssessmentImporter, "model": Assessment, "policy": AssessmentImportPolicy},
}


def has(kind: str) -> bool:
    return kind in TYPES


def importer(kind: str):
    """A fresh importer each time: they cache the school's sections while they
    work, which is only ever right for one import."""
    return TYPES[kind]["importer"]()


def policy(kind: str):
    return TYPES[kind]["policy"]

"""Fee heads and fee structures: step F1, "Fee Set-up" (docs/fees.md).

Views decide who may ask; this decides what happens, and writes every change
to the audit log in the same transaction as the change itself. From F2,
publishing a fee and editing a published one also charge the students it
reaches (fees/dues.py), in that same transaction.
"""

from __future__ import annotations

from django.db import IntegrityError, transaction
from django.db.models import Count, Q
from django.utils import timezone
from rest_framework import serializers

from .. import audit
from ..enums import FeeDueStatus, FeeStructureStatus
from ..errors import FeeHeadInUse, FeeHeadLimitReached, FeeHeadProtected, FeeStructurePublished
from ..models import FeeHead, FeeInstallment, FeeStructure, ModuleSetting, School, StudentFeeDue
from ..scope import SchoolScope
from ..validation import already_taken
from .dues import FeeDueService, SyncResult
from .requests import duplicate_message

MODULE = "fees"
TRANSPORT = "Transport"

# Fee types per school, Transport included.
MAX_HEADS = 50


# -- fee heads ----------------------------------------------------------------


class FeeHeadService:
    @staticmethod
    def ensure_transport(school_id: int) -> FeeHead:
        """Every school has a Transport head: bus route fees hang off it.

        Created the first time anybody reads the school's heads or writes a
        structure. Race-safe through the (school_id, name) unique key: two
        requests that both find it missing both try, one wins, and the other
        reads the winner's row.
        """
        head = FeeHead.objects.filter(school_id=school_id, is_transport=True).first()

        if head is not None:
            return head

        now = timezone.now()

        try:
            with transaction.atomic():
                return FeeHead.objects.create(
                    school_id=school_id, name=TRANSPORT, is_transport=True, is_active=True,
                    created_at=now, updated_at=now,
                )
        except IntegrityError:
            # Somebody else made it a moment ago - or a head was typed as
            # "Transport" before this rule existed, which becomes the one.
            head = FeeHead.objects.get(school_id=school_id, name=TRANSPORT)

            if not head.is_transport or not head.is_active:
                head.is_transport = True
                head.is_active = True
                head.updated_at = now
                head.save(update_fields=["is_transport", "is_active", "updated_at"])

            return head

    @classmethod
    def ensure_transport_for(cls, school_ids) -> None:
        for school_id in school_ids:
            cls.ensure_transport(school_id)

    @classmethod
    def visible_to(cls, actor, requested_school) -> list[FeeHead]:
        """The heads an actor may read, Transport first, then the active ones
        by name, then the retired ones by name - each school's together.

        A school-bound actor reads their own school's. One who spans several
        - a Super Admin, a Group Admin - reads the one they name, or every
        school in their scope that has the module on when they name none,
        the way payroll's lists do. A school named outside the scope is
        ignored rather than honoured (SchoolScope.apply_to).
        """
        school_ids = cls.schools_with_fees(actor, requested_school)
        cls.ensure_transport_for(school_ids)

        heads = list(FeeHead.objects.filter(school_id__in=school_ids).annotate(structures_count=Count("structures")))

        return sorted(heads, key=head_order)

    @staticmethod
    def schools_with_fees(actor, requested_school) -> list[int]:
        """The schools in this read that have Fee Management on: both
        switches on, since the module is not granted by default."""
        on = ModuleSetting.objects.filter(module=MODULE, platform_enabled=True, school_enabled=True)
        schools = SchoolScope.for_actor(actor).apply_to(School.objects.all(), requested_school, column="id")

        return list(schools.filter(id__in=on.values("school_id")).order_by("id").values_list("id", flat=True))

    @staticmethod
    def with_count(head_id: int) -> FeeHead:
        return FeeHead.objects.annotate(structures_count=Count("structures")).get(pk=head_id)

    @classmethod
    def create(cls, school_id: int, name: str, actor, request=None) -> FeeHead:
        with transaction.atomic():
            # One writer per school at a time, so neither the case-blind
            # name rule nor the cap can be raced past.
            School.objects.select_for_update().filter(pk=school_id).first()
            cls.ensure_transport(school_id)

            cls.assert_name_free(school_id, name)

            if FeeHead.objects.filter(school_id=school_id).count() >= MAX_HEADS:
                raise FeeHeadLimitReached(
                    f"A school can have at most {MAX_HEADS} fee types. Delete or reuse one you no longer need."
                )

            now = timezone.now()
            head = FeeHead.objects.create(
                school_id=school_id, name=name, is_transport=False, is_active=True, created_at=now, updated_at=now,
            )

            audit.record(
                actor=actor, action="fee_head.created", module=MODULE, entity_type="fee_head", entity_id=head.id,
                school_id=school_id, new=cls.snapshot(head), request=request,
            )

        return head

    @classmethod
    def update(cls, head: FeeHead, data: dict, actor, request=None) -> FeeHead:
        renaming = "name" in data and data["name"] != head.name
        retiring = data.get("is_active") is False

        if head.is_transport and (renaming or retiring):
            raise FeeHeadProtected()

        with transaction.atomic():
            School.objects.select_for_update().filter(pk=head.school_id).first()
            head = FeeHead.objects.select_for_update().get(pk=head.pk)
            before = cls.snapshot(head)

            if renaming:
                cls.assert_name_free(head.school_id, data["name"], ignoring=head.id)
                head.name = data["name"]

            if "is_active" in data:
                head.is_active = data["is_active"]

            if cls.snapshot(head) != before:
                head.updated_at = timezone.now()
                head.save()

                audit.record(
                    actor=actor, action="fee_head.updated", module=MODULE, entity_type="fee_head", entity_id=head.id,
                    school_id=head.school_id, old=before, new=cls.snapshot(head), request=request,
                )

        return head

    @classmethod
    def delete(cls, head: FeeHead, actor, request=None) -> None:
        if head.is_transport:
            raise FeeHeadProtected()

        with transaction.atomic():
            head = FeeHead.objects.select_for_update().get(pk=head.pk)
            used = FeeStructure.objects.filter(fee_head_id=head.id).count()

            if used:
                raise FeeHeadInUse(
                    f"This fee type is used by {used} {'fee' if used == 1 else 'fees'}. Retire it instead."
                )

            audit.record(
                actor=actor, action="fee_head.deleted", module=MODULE, entity_type="fee_head", entity_id=head.id,
                school_id=head.school_id, old=cls.snapshot(head), request=request,
            )
            head.delete()

    @staticmethod
    def assert_name_free(school_id: int, name: str, ignoring: int | None = None) -> None:
        """Unique per school without regard to case. Asked with iexact
        because PostgreSQL compares case-sensitively, and "tuition" beside
        "Tuition" is the same fee typed twice."""
        taken = FeeHead.objects.filter(school_id=school_id, name__iexact=name)

        if ignoring is not None:
            taken = taken.exclude(pk=ignoring)

        if taken.exists():
            raise serializers.ValidationError({"name": [already_taken("name")]})

    @staticmethod
    def snapshot(head: FeeHead) -> dict:
        return {"name": head.name, "is_transport": head.is_transport, "is_active": head.is_active}


def head_order(head: FeeHead) -> tuple:
    return (head.school_id, not head.is_transport, not head.is_active, head.name.lower(), head.id)


# -- fee structures -----------------------------------------------------------


class FeeStructureService:
    WITH = ("school", "academic_year", "school_class", "transport_route", "fee_head")

    @classmethod
    def for_year(cls, year, kind: str | None) -> list[FeeStructure]:
        """A year's fees: the classes in class order, then the routes by
        name, each with its heads by name. Sorted here rather than in SQL
        because NULLs (a route has no class) sort differently on MySQL and
        PostgreSQL."""
        structures = cls.with_students().filter(academic_year_id=year.id)

        if kind == "class":
            structures = structures.filter(school_class__isnull=False)
        elif kind == "route":
            structures = structures.filter(transport_route__isnull=False)

        return sorted(structures, key=structure_order)

    @classmethod
    def with_students(cls):
        """Fees with `students_count`: the students each one charges now -
        distinct students with a due of it that is not cancelled. Always 0
        for a draft, which charges nobody."""
        return (
            FeeStructure.objects.select_related(*cls.WITH)
            .prefetch_related("installments")
            .annotate(students_count=Count(
                "dues__student", filter=~Q(dues__status=FeeDueStatus.CANCELLED), distinct=True
            ))
        )

    @classmethod
    def load(cls, structure_id: int) -> FeeStructure:
        return cls.with_students().get(pk=structure_id)

    @classmethod
    def create(cls, data: dict, actor, request=None) -> FeeStructure:
        year = data["academic_year"]
        now = timezone.now()

        with transaction.atomic():
            cls.ensure_transport_head(year.school_id)

            try:
                with transaction.atomic():
                    structure = FeeStructure.objects.create(
                        school_id=year.school_id,
                        academic_year=year,
                        school_class=data["school_class"],
                        transport_route=data["transport_route"],
                        fee_head=data["fee_head"],
                        amount=data["amount"],
                        # The school's currency today, kept with the fee -
                        # CLAUDE.md rule 5. Never the client's to say.
                        currency_code=year.school.currency_code,
                        frequency=data["frequency"],
                        status=FeeStructureStatus.DRAFT,
                        created_by=actor,
                        created_at=now,
                        updated_at=now,
                    )
            except IntegrityError:
                # Two people saving the same fee at the same moment: the
                # second meets the unique key, and hears what the form would
                # have told them a second later.
                raise serializers.ValidationError({
                    "fee_head_id": [duplicate_message(year, data["school_class"], data["transport_route"], data["fee_head"])]
                })

            cls.write_installments(structure, data["installments"], now)

            audit.record(
                actor=actor, action="fee_structure.created", module=MODULE, entity_type="fee_structure",
                entity_id=structure.id, school_id=structure.school_id, new=cls.snapshot(structure), request=request,
            )

        return structure

    @classmethod
    def update(cls, structure: FeeStructure, data: dict, actor, request=None) -> FeeStructure:
        """Replaces the amount, the frequency and the installments.

        A draft's installments are replaced wholesale. A published fee's are
        edited in place, by position, because students' dues point at them:
        the first N keep their rows and take the new label, date and amount,
        extra ones are added, and one dropped from the end goes only if no
        student is still charged it. Then everybody the fee reaches is
        reconciled - unpaid dues follow, part-paid ones never drop below
        what was paid, paid ones are untouched (docs/fees.md, "Changes never
        rewrite history").
        """
        with transaction.atomic():
            structure = FeeStructure.objects.select_for_update().get(pk=structure.pk)
            before = cls.snapshot(structure)
            now = timezone.now()
            published = structure.status == FeeStructureStatus.PUBLISHED

            if published:
                cls.assert_removable(structure, len(data["installments"]))

            structure.amount = data["amount"]
            structure.frequency = data["frequency"]
            structure.updated_at = now
            structure.save(update_fields=["amount", "frequency", "updated_at"])

            if published:
                cls.edit_installments_in_place(structure, data["installments"], now)
            else:
                FeeInstallment.objects.filter(fee_structure_id=structure.id).delete()
                cls.write_installments(structure, data["installments"], now)

            audit.record(
                actor=actor, action="fee_structure.updated", module=MODULE, entity_type="fee_structure",
                entity_id=structure.id, school_id=structure.school_id, old=before, new=cls.snapshot(structure),
                request=request,
            )

            if published:
                charged = FeeDueService.sync_structures([structure], structure.academic_year)
                FeeDueService.audit(charged, entity_type="fee_structure", entity_id=structure.id,
                                    school_id=structure.school_id, actor=actor, request=request)

        return structure

    @staticmethod
    def assert_removable(structure: FeeStructure, keeping: int) -> None:
        """A published fee may lose installments from the end only where no
        student is charged them any more."""
        charged = sorted(set(
            StudentFeeDue.objects.filter(fee_structure_id=structure.id, fee_installment__sequence__gt=keeping)
            .exclude(status=FeeDueStatus.CANCELLED)
            .values_list("fee_installment__sequence", flat=True)
        ))

        if charged:
            raise serializers.ValidationError({
                "installments": [
                    f"Installment {sequence} already has students charged. "
                    "Change its amount or date instead of removing it."
                    for sequence in charged
                ]
            })

    @classmethod
    def edit_installments_in_place(cls, structure: FeeStructure, installments: list[dict], now) -> None:
        existing = {row.sequence: row for row in FeeInstallment.objects.filter(fee_structure_id=structure.id)}
        changed, added = [], []

        for row in installments:
            current = existing.get(row["sequence"])

            if current is None:
                added.append(row)
                continue

            current.label, current.due_date, current.amount = row["label"], row["due_date"], row["amount"]
            current.updated_at = now
            changed.append(current)

        if changed:
            FeeInstallment.objects.bulk_update(changed, ["label", "due_date", "amount", "updated_at"])

        if added:
            cls.write_installments(structure, added, now)

        removed = [row.id for sequence, row in existing.items() if sequence > len(installments)]

        if removed:
            # Only cancelled dues can still point at these (assert_removable
            # saw to that): the record of a fee that never applied, cleared so
            # the installment can go.
            cleared = StudentFeeDue.objects.filter(fee_installment_id__in=removed, status=FeeDueStatus.CANCELLED)
            # A late fine on one of them stays owed in its own right (F4); it
            # just stops pointing at a line that is gone - the migration's
            # nullOnDelete, spelled out for the test database that has none.
            cleared_ids = list(cleared.values_list("id", flat=True))
            StudentFeeDue.objects.filter(fine_for_due_id__in=cleared_ids).update(fine_for_due_id=None)
            cleared.delete()
            FeeInstallment.objects.filter(pk__in=removed).delete()

    @classmethod
    def delete(cls, structure: FeeStructure, actor, request=None) -> None:
        with transaction.atomic():
            structure = FeeStructure.objects.select_for_update().get(pk=structure.pk)

            if structure.status == FeeStructureStatus.PUBLISHED:
                raise FeeStructurePublished()

            before = cls.snapshot(structure)

            # Spelled out rather than left to the migration's cascade: the
            # test database is built from the models and has none.
            FeeInstallment.objects.filter(fee_structure_id=structure.id).delete()
            structure_id, school_id = structure.id, structure.school_id
            structure.delete()

            audit.record(
                actor=actor, action="fee_structure.deleted", module=MODULE, entity_type="fee_structure",
                entity_id=structure_id, school_id=school_id, old=before, request=request,
            )

    @classmethod
    def publish(cls, structure: FeeStructure, actor, request=None) -> tuple[FeeStructure, SyncResult]:
        """Draft to published, one way, charging every student the fee
        reaches in the same transaction. Publishing a published fee again
        writes nothing to the audit log, and its reconcile finds nothing to
        do - so nobody is ever charged twice."""
        with transaction.atomic():
            structure = FeeStructure.objects.select_for_update().get(pk=structure.pk)
            cls.mark_published(structure, actor, request)

            charged = FeeDueService.sync_structures([structure], structure.academic_year)
            FeeDueService.audit(charged, entity_type="fee_structure", entity_id=structure.id,
                                school_id=structure.school_id, actor=actor, request=request)

        return structure, charged

    @classmethod
    def publish_all(cls, year, actor, request=None) -> tuple[int, SyncResult]:
        """Every draft of one academic year, in one transaction, each student
        reconciled once however many of the fees reach them."""
        with transaction.atomic():
            drafts = list(
                FeeStructure.objects.select_for_update()
                .filter(academic_year_id=year.id, status=FeeStructureStatus.DRAFT)
                .order_by("id")
            )

            for structure in drafts:
                cls.mark_published(structure, actor, request)

            charged = FeeDueService.sync_structures(drafts, year)
            # One row for the whole action, on the year it published: the
            # counts are the action's, not any one fee's.
            FeeDueService.audit(charged, entity_type="academic_year", entity_id=year.id,
                                school_id=year.school_id, actor=actor, request=request)

        return len(drafts), charged

    @classmethod
    def mark_published(cls, structure: FeeStructure, actor, request) -> None:
        if structure.status == FeeStructureStatus.PUBLISHED:
            return

        before = {"status": structure.status, "published_at": None}
        now = timezone.now()
        structure.status = FeeStructureStatus.PUBLISHED
        structure.published_at = now
        structure.published_by = actor
        structure.updated_at = now
        structure.save(update_fields=["status", "published_at", "published_by", "updated_at"])

        audit.record(
            actor=actor, action="fee_structure.published", module=MODULE, entity_type="fee_structure",
            entity_id=structure.id, school_id=structure.school_id, old=before,
            new={"status": structure.status, "published_at": structure.published_at}, request=request,
        )

    @staticmethod
    def ensure_transport_head(school_id: int) -> None:
        FeeHeadService.ensure_transport(school_id)

    @staticmethod
    def write_installments(structure: FeeStructure, installments: list[dict], now) -> None:
        FeeInstallment.objects.bulk_create([
            FeeInstallment(
                fee_structure=structure,
                sequence=row["sequence"],
                label=row["label"],
                due_date=row["due_date"],
                amount=row["amount"],
                created_at=now,
                updated_at=now,
            )
            for row in installments
        ])

    @staticmethod
    def snapshot(structure: FeeStructure) -> dict:
        return {
            "academic_year_id": structure.academic_year_id,
            "school_class_id": structure.school_class_id,
            "transport_route_id": structure.transport_route_id,
            "fee_head_id": structure.fee_head_id,
            "amount": structure.amount,
            "currency_code": structure.currency_code,
            "frequency": structure.frequency,
            "status": structure.status,
            "installments": [
                {"sequence": row.sequence, "label": row.label, "due_date": row.due_date, "amount": row.amount}
                for row in FeeInstallment.objects.filter(fee_structure_id=structure.id).order_by("sequence")
            ],
        }


def structure_order(structure: FeeStructure) -> tuple:
    if structure.school_class_id is not None:
        place = (0, structure.school_class.level, structure.school_class.name.lower())
    else:
        place = (1, 0, structure.transport_route.name.lower())

    return (*place, structure.fee_head.name.lower(), structure.id)

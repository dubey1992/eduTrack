"""Which schools an actor is allowed to touch.

A direct port of backend/app/Support/SchoolScope.php, and deliberately a dull
one. This is the single most important file in the migration: the PHP version
replaced well over a hundred inline `role === SuperAdmin || school_id === x`
checks, and every one of those was a chance to get isolation wrong. Rewriting
the *idea* here rather than the code would mean two answers to one question,
which is exactly how one school ends up reading another's records.

So the method names, the fallbacks and the odd-looking decisions all come
across unchanged, and where something reads strangely the comment saying why
came with it.

Mostly a value object built from a User that is already loaded. The exception
is an admin role, which has to ask which schools are in its group - so building
one of those reads the `schools` table.
"""

from __future__ import annotations

from django.db.models import Q, QuerySet

from .enums import UserRole
from .models import School, User


class SchoolScope:
    """`school_ids` is None for an actor who answers for every school there is."""

    def __init__(self, school_ids: list[int] | None) -> None:
        self._school_ids = school_ids

    # -- construction ------------------------------------------------------

    @classmethod
    def for_actor(cls, actor: User) -> "SchoolScope":
        if actor.role == UserRole.SUPER_ADMIN:
            return cls.unrestricted()

        # Both admin roles answer for a whole group: a Group Admin from the
        # parent it is attached to, a School Admin from whichever branch it
        # sits in. Either way it is that school's group and nothing outside
        # it, however the request is edited.
        #
        # For a standalone school - which is most of them - the group is just
        # that school, so this resolves to exactly what it always did and
        # nothing about those schools changes.
        if UserRole.administers_school(actor.role):
            return cls._group_of(actor)

        # Everybody else lives in exactly one school. A Teacher at North
        # teaches at North; the group is an administrative idea, not a
        # teaching one. An account with no school at all - which should not
        # happen outside a half-finished fixture - can see nothing, rather
        # than mysteriously matching every record whose school_id is also
        # null.
        return cls([] if actor.school_id is None else [actor.school_id])

    @classmethod
    def _group_of(cls, actor: User) -> "SchoolScope":
        """The group an admin answers for: their school, plus its parent and
        sisters, or its branches.

        Falls back to the school id on the account when the school itself
        cannot be read - a row deleted out from under it, or a user built
        without one. "Their own school and no other" is the right answer for
        an admin whatever else is wrong; resolving to nothing would hide their
        own records from them with no error to explain it.
        """
        group = group_school_ids(actor.school_id)

        if group is None:
            return cls([] if actor.school_id is None else [actor.school_id])

        return cls.of(group)

    @classmethod
    def unrestricted(cls) -> "SchoolScope":
        return cls(None)

    @classmethod
    def of(cls, school_ids) -> "SchoolScope":
        # dict.fromkeys rather than a set: unique, but keeping the order the
        # ids arrived in, so a scope reads the same way twice running.
        return cls(list(dict.fromkeys(int(school_id) for school_id in school_ids)))

    # -- questions ---------------------------------------------------------

    def is_unrestricted(self) -> bool:
        """True for an actor who belongs to no school and answers for all of them."""
        return self._school_ids is None

    def covers_a_group(self) -> bool:
        """True when this scope covers several named schools - a group.

        The distinction a report needs: a group can be reported on as a whole
        because it is a handful of branches, while "every school on the
        platform" cannot, and a Super Admin is asked to name one.
        """
        return self._school_ids is not None and len(self._school_ids) > 1

    def allows(self, school_id: int | None) -> bool:
        if self.is_unrestricted():
            return True

        return school_id is not None and int(school_id) in self._school_ids

    def ids(self) -> list[int] | None:
        """The schools in scope, or None for every school."""
        return self._school_ids

    def default_school_id(self) -> int | None:
        """The school a write lands in when the request does not name one.

        None when that is genuinely ambiguous - an unrestricted actor, or one
        who spans several schools - in which case the request has to say.
        """
        if self._school_ids is not None and len(self._school_ids) == 1:
            return self._school_ids[0]

        return None

    # -- applying ----------------------------------------------------------

    def apply_to(self, queryset: QuerySet, requested=None, column: str = "school_id") -> QuerySet:
        """Limits a query to what this actor may see, optionally narrowed
        further to one school they asked for.

        A requested school can only narrow, never widen: one outside the scope
        is ignored rather than honoured, which leaves the actor looking at
        their own records instead of somebody else's. That is exactly what the
        hand-written version did, and changing it would be a security decision
        dressed up as a refactor.
        """
        requested = self.requested_id(requested)

        if self._school_ids is not None:
            queryset = queryset.filter(**{column + "__in": self._school_ids})

        if requested is not None and self.allows(requested):
            queryset = queryset.filter(**{column: requested})

        return queryset

    @staticmethod
    def requested_id(value) -> int | None:
        """Reads a school id off a filter, which arrives as whatever was in
        the query string.

        Absent or blank means no filter. Anything that is not a number becomes
        0 - an id no school has - so a nonsense filter matches nothing, which
        is what the PHP version's `where('school_id', 'abc')` did. It must
        never come out as "no filter", or garbage would widen the result
        instead of narrowing it.
        """
        if value is None or value == "":
            return None

        try:
            return int(str(value).strip())
        except (TypeError, ValueError):
            return 0

    def writable_school_id(self, requested: int | None) -> int | None:
        """The school a write should be filed under, given what the request
        asked for.

        An actor who may only write into one school writes into it whatever
        the request says - the client's school_id is never trusted (CLAUDE.md
        rule 10). An unrestricted one gets back exactly what they asked for,
        having already had to pass validation that the school exists.
        """
        if self.is_unrestricted():
            return requested

        if requested is not None and self.allows(requested):
            return requested

        return self.default_school_id()


def group_school_ids(school_id: int | None) -> list[int] | None:
    """Every school in one school's group - itself, plus its branches if it is
    a parent, or its parent and sisters if it is a branch.

    Deliberately one level deep, matching School::groupSchoolIds(): a group of
    groups would need a recursive query and nothing in the product asks for
    one.

    None means "there is no such school to ask about", which is what lets the
    caller tell that apart from a school that simply has no branches.
    """
    if school_id is None:
        return None

    school = School.objects.filter(pk=school_id).values("id", "parent_school_id").first()

    if school is None:
        return None

    root_id = school["parent_school_id"] or school["id"]

    return list(
        School.objects.filter(Q(pk=root_id) | Q(parent_school_id=root_id))
        .order_by("id")
        .values_list("id", flat=True)
    )

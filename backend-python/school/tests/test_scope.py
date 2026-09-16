"""SchoolScope, which decides what every other test in this suite is about.

The migration plan names a policy ported subtly wrong as the second most
likely way this goes badly, and the ALLOW/DENY pairs as the whole defence. So
each rule below is asserted in both directions: what the actor may reach, and
what they may not. A test that only checks the allow half passes just as
happily against a scope that allows everything.

The shapes being tested come from docs/branches.md - a branch is a school row
with a parent, and nothing else distinguishes it.
"""

from django.test import TestCase

from school import factories
from school.enums import UserRole
from school.models import Student
from school.scope import SchoolScope, group_school_ids


class AStandaloneSchool(TestCase):
    """Most schools. Nothing about groups should change any of this."""

    def setUp(self):
        self.school = factories.SchoolFactory()
        self.other = factories.SchoolFactory()

    def test_an_admin_reaches_their_own_school(self):
        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        )

        self.assertTrue(scope.allows(self.school.id))
        self.assertFalse(scope.allows(self.other.id))

    def test_an_admin_of_a_standalone_school_does_not_manage_branches(self):
        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        )

        self.assertFalse(scope.covers_a_group())
        self.assertEqual(self.school.id, scope.default_school_id())

    def test_a_teacher_reaches_exactly_one_school(self):
        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        )

        self.assertEqual([self.school.id], scope.ids())
        self.assertFalse(scope.allows(self.other.id))

    def test_a_super_admin_reaches_everything(self):
        scope = SchoolScope.for_actor(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertTrue(scope.is_unrestricted())
        self.assertTrue(scope.allows(self.school.id))
        self.assertTrue(scope.allows(self.other.id))
        self.assertIsNone(scope.ids())

    def test_a_super_admin_has_no_default_school_to_write_into(self):
        # Which is why every create form makes them name one: a Super Admin
        # belongs to no school, so "their school" is not a thing that exists.
        scope = SchoolScope.for_actor(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertIsNone(scope.default_school_id())

    def test_an_account_with_no_school_reaches_nothing(self):
        # Should not happen outside a half-finished fixture. The point is that
        # it resolves to nothing rather than mysteriously matching every
        # record whose school_id is also null.
        scope = SchoolScope.for_actor(factories.UserFactory(school=None, role=UserRole.TEACHER))

        self.assertEqual([], scope.ids())
        self.assertFalse(scope.allows(None))
        self.assertFalse(scope.allows(self.school.id))


class AGroupOfSchools(TestCase):
    def setUp(self):
        self.group = factories.SchoolFactory(name="St Mary's Group")
        self.north = factories.SchoolFactory(name="St Mary's North", parent_school=self.group)
        self.south = factories.SchoolFactory(name="St Mary's South", parent_school=self.group)
        self.outsider = factories.SchoolFactory(name="Unrelated High")

    def test_a_group_admin_reaches_the_parent_and_every_branch(self):
        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.group, role=UserRole.GROUP_ADMIN)
        )

        self.assertEqual([self.group.id, self.north.id, self.south.id], scope.ids())
        self.assertFalse(scope.allows(self.outsider.id))

    def test_a_branch_admin_looks_up_at_the_parent_and_across_at_its_sister(self):
        # The rule the head of a school asked for: they answer for the whole
        # group, so a branch admin sees the parent and the sister branches,
        # not only their own building.
        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN)
        )

        self.assertTrue(scope.allows(self.group.id))
        self.assertTrue(scope.allows(self.south.id))
        self.assertTrue(scope.allows(self.north.id))
        self.assertFalse(scope.allows(self.outsider.id))

    def test_a_teacher_at_a_branch_stays_at_that_branch(self):
        # The group is an administrative idea, not a teaching one. A teacher
        # at North teaches at North.
        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.north, role=UserRole.TEACHER)
        )

        self.assertEqual([self.north.id], scope.ids())
        self.assertFalse(scope.allows(self.south.id))
        self.assertFalse(scope.allows(self.group.id))

    def test_an_admin_in_a_group_has_no_single_default_school(self):
        # Which is what makes the client ask "which branch?" on every create
        # form - and what `manages_branches` tells it.
        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN)
        )

        self.assertTrue(scope.covers_a_group())
        self.assertIsNone(scope.default_school_id())

    def test_the_group_is_one_level_deep(self):
        # A branch of a branch is not a thing the product has, and resolving
        # it silently would give one admin reach nobody granted.
        sub_branch = factories.SchoolFactory(name="North Annexe", parent_school=self.north)

        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.group, role=UserRole.GROUP_ADMIN)
        )

        self.assertFalse(scope.allows(sub_branch.id))


class NarrowingAQuery(TestCase):
    def setUp(self):
        self.group = factories.SchoolFactory()
        self.branch = factories.SchoolFactory(parent_school=self.group)
        self.outsider = factories.SchoolFactory()

        self.ours = factories.StudentFactory(
            school=self.branch, class_section=section_in(self.branch)
        )
        self.theirs = factories.StudentFactory(
            school=self.outsider, class_section=section_in(self.outsider)
        )

    def test_a_scoped_query_sees_only_the_group(self):
        admin = factories.UserFactory(school=self.branch, role=UserRole.SCHOOL_ADMIN)

        visible = SchoolScope.for_actor(admin).apply_to(Student.objects.all())

        self.assertEqual([self.ours.id], [student.id for student in visible])

    def test_an_unrestricted_query_is_not_filtered(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        visible = SchoolScope.for_actor(root).apply_to(Student.objects.all())

        self.assertEqual(
            {self.ours.id, self.theirs.id},
            {student.id for student in visible},
        )

    def test_naming_another_school_leaves_the_actor_looking_at_their_own(self):
        # The rule this whole class exists for, and the half of it that is
        # easy to get wrong. A school_id in the query string can only narrow.
        # One outside the scope is *ignored* - not honoured, and not an error
        # either - so the actor is left looking at their own records rather
        # than somebody else's.
        admin = factories.UserFactory(school=self.branch, role=UserRole.SCHOOL_ADMIN)

        visible = SchoolScope.for_actor(admin).apply_to(
            Student.objects.all(), requested=self.outsider.id
        )

        self.assertEqual([self.ours.id], [student.id for student in visible])
        self.assertNotIn(self.theirs.id, [student.id for student in visible])

    def test_a_nonsense_filter_matches_nothing_rather_than_everything(self):
        # "abc" must not come out as "no filter", or garbage in a query string
        # would widen the result instead of narrowing it.
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        visible = SchoolScope.for_actor(root).apply_to(Student.objects.all(), requested="abc")

        self.assertEqual([], [student.id for student in visible])
        self.assertEqual(0, SchoolScope.requested_id("abc"))
        self.assertIsNone(SchoolScope.requested_id(""))
        self.assertIsNone(SchoolScope.requested_id(None))


class WhereAWriteLands(TestCase):
    def setUp(self):
        self.school = factories.SchoolFactory()
        self.other = factories.SchoolFactory()

    def test_an_actor_with_one_school_writes_into_it_whatever_the_request_says(self):
        # CLAUDE.md rule 10, asserted rather than trusted: the client's
        # school_id is never trusted.
        scope = SchoolScope.for_actor(
            factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)
        )

        self.assertEqual(self.school.id, scope.writable_school_id(self.other.id))
        self.assertEqual(self.school.id, scope.writable_school_id(None))

    def test_a_super_admin_writes_where_they_asked(self):
        scope = SchoolScope.for_actor(factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN))

        self.assertEqual(self.other.id, scope.writable_school_id(self.other.id))

    def test_a_group_admin_writes_into_the_branch_they_named(self):
        group = factories.SchoolFactory()
        north = factories.SchoolFactory(parent_school=group)

        scope = SchoolScope.for_actor(factories.UserFactory(school=group, role=UserRole.GROUP_ADMIN))

        self.assertEqual(north.id, scope.writable_school_id(north.id))

    def test_a_group_admin_naming_an_outsider_gets_nowhere_rather_than_the_outsider(self):
        group = factories.SchoolFactory()
        factories.SchoolFactory(parent_school=group)

        scope = SchoolScope.for_actor(factories.UserFactory(school=group, role=UserRole.GROUP_ADMIN))

        # None, not the outsider: there is no single school to fall back to,
        # so the write has no home and the form has to refuse it.
        self.assertIsNone(scope.writable_school_id(self.other.id))


class WhenTheSchoolCannotBeRead(TestCase):
    def test_an_admin_falls_back_to_their_own_school_id(self):
        # A row deleted out from under the account, or a user built without
        # one. "Their own school and no other" is the right answer for an
        # admin whatever else is wrong; resolving to nothing would hide their
        # own records from them with no error to explain it.
        school = factories.SchoolFactory()
        admin = factories.UserFactory(school=school, role=UserRole.SCHOOL_ADMIN)

        admin.school_id = school.id + 10_000

        scope = SchoolScope.for_actor(admin)

        self.assertEqual([admin.school_id], scope.ids())

    def test_group_school_ids_says_nothing_for_a_school_that_is_not_there(self):
        self.assertIsNone(group_school_ids(None))
        self.assertIsNone(group_school_ids(9_999_999))


def section_in(school):
    """A class section belonging to `school`, built through its own class."""
    year = factories.AcademicYearFactory(school=school)
    school_class = factories.SchoolClassFactory(academic_year=year, school=school)

    return factories.ClassSectionFactory(school_class=school_class)

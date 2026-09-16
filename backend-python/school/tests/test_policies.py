"""StudentPolicy, in both directions.

Every rule gets an ALLOW test and a DENY test (CLAUDE.md rule 11). The DENY
half is the one that matters: a policy that has accidentally been written to
return True does not fail a single ALLOW test.
"""

from django.test import TestCase

from school import factories
from school.enums import UserRole
from school.policies import StudentPolicy

from .test_scope import section_in


class WhoMayReadTheRoll(TestCase):
    def setUp(self):
        self.school = factories.SchoolFactory()
        self.section = section_in(self.school)
        self.student = factories.StudentFactory(school=self.school, class_section=self.section)

    def admin(self, role=UserRole.SCHOOL_ADMIN, school=None):
        return factories.UserFactory(school=school or self.school, role=role)

    def test_an_admin_of_the_school_may_read_it(self):
        self.assertTrue(StudentPolicy.view(self.admin(), self.student))

    def test_an_admin_of_another_school_may_not(self):
        outsider = self.admin(school=factories.SchoolFactory())

        self.assertFalse(StudentPolicy.view(outsider, self.student))

    def test_a_super_admin_may_read_any_student(self):
        root = factories.UserFactory(school=None, role=UserRole.SUPER_ADMIN)

        self.assertTrue(StudentPolicy.view(root, self.student))

    def test_the_class_teacher_may_read_their_own_students(self):
        teacher = self.admin(role=UserRole.TEACHER)
        self.section.class_teacher_id = teacher.id
        self.section.save()
        self.student.refresh_from_db()

        self.assertTrue(StudentPolicy.view(teacher, self.student))

    def test_a_teacher_of_another_section_may_not(self):
        # "A Teacher assigned to 8A must not access 9A" - CLAUDE.md, and the
        # single most specific authorization rule in the product.
        teacher = self.admin(role=UserRole.TEACHER)
        other_section = section_in(self.school)
        other_section.class_teacher_id = teacher.id
        other_section.save()

        self.assertFalse(StudentPolicy.view(teacher, self.student))

    def test_a_teacher_in_the_same_school_teaching_nothing_may_not(self):
        teacher = self.admin(role=UserRole.TEACHER)

        self.assertFalse(StudentPolicy.view(teacher, self.student))

    def test_roles_with_no_student_access_have_none(self):
        for role in (UserRole.HOD, UserRole.STAFF, UserRole.TRANSPORT_MANAGER):
            with self.subTest(role=role):
                actor = self.admin(role=role)

                self.assertFalse(StudentPolicy.view(actor, self.student))
                self.assertFalse(StudentPolicy.view_any(actor))
                self.assertFalse(StudentPolicy.create(actor))

    def test_view_any_admits_admins_and_teachers(self):
        for role in (
            UserRole.SUPER_ADMIN,
            UserRole.GROUP_ADMIN,
            UserRole.SCHOOL_ADMIN,
            UserRole.TEACHER,
        ):
            with self.subTest(role=role):
                self.assertTrue(StudentPolicy.view_any(self.admin(role=role)))


class WhoMayChangeTheRoll(TestCase):
    def setUp(self):
        self.school = factories.SchoolFactory()
        self.student = factories.StudentFactory(
            school=self.school, class_section=section_in(self.school)
        )

    def test_an_admin_of_the_school_may_edit_and_deactivate(self):
        admin = factories.UserFactory(school=self.school, role=UserRole.SCHOOL_ADMIN)

        self.assertTrue(StudentPolicy.update(admin, self.student))
        self.assertTrue(StudentPolicy.set_status(admin, self.student))

    def test_an_admin_of_another_school_may_do_neither(self):
        outsider = factories.UserFactory(school=factories.SchoolFactory(), role=UserRole.SCHOOL_ADMIN)

        self.assertFalse(StudentPolicy.update(outsider, self.student))
        self.assertFalse(StudentPolicy.set_status(outsider, self.student))

    def test_a_teacher_may_read_but_not_write(self):
        # The one asymmetry in this policy, and the reason view() and
        # update() are not the same method.
        section = self.student.class_section
        teacher = factories.UserFactory(school=self.school, role=UserRole.TEACHER)
        section.class_teacher_id = teacher.id
        section.save()
        self.student.refresh_from_db()

        self.assertTrue(StudentPolicy.view(teacher, self.student))
        self.assertFalse(StudentPolicy.update(teacher, self.student))
        self.assertFalse(StudentPolicy.set_status(teacher, self.student))
        self.assertFalse(StudentPolicy.create(teacher))


class AcrossAGroup(TestCase):
    def setUp(self):
        self.group = factories.SchoolFactory()
        self.north = factories.SchoolFactory(parent_school=self.group)
        self.south = factories.SchoolFactory(parent_school=self.group)
        self.outsider = factories.SchoolFactory()

        self.southern_student = factories.StudentFactory(
            school=self.south, class_section=section_in(self.south)
        )
        self.outside_student = factories.StudentFactory(
            school=self.outsider, class_section=section_in(self.outsider)
        )

    def test_a_branch_admin_manages_a_sister_branchs_students(self):
        admin = factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN)

        self.assertTrue(StudentPolicy.view(admin, self.southern_student))
        self.assertTrue(StudentPolicy.update(admin, self.southern_student))

    def test_a_branch_admin_still_reaches_nothing_outside_the_group(self):
        admin = factories.UserFactory(school=self.north, role=UserRole.SCHOOL_ADMIN)

        self.assertFalse(StudentPolicy.view(admin, self.outside_student))
        self.assertFalse(StudentPolicy.update(admin, self.outside_student))

    def test_a_group_admin_manages_every_branch(self):
        admin = factories.UserFactory(school=self.group, role=UserRole.GROUP_ADMIN)

        self.assertTrue(StudentPolicy.view(admin, self.southern_student))
        self.assertFalse(StudentPolicy.view(admin, self.outside_student))

    def test_a_teacher_at_one_branch_does_not_reach_the_sister(self):
        teacher = factories.UserFactory(school=self.north, role=UserRole.TEACHER)

        self.assertFalse(StudentPolicy.view(teacher, self.southern_student))

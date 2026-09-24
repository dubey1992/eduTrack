"""What M7 claims, asserted.

The skeleton's job is narrow: describe the tables Laravel owns, and be able to
build enough of a school to test against. Endpoints come at M8. So these tests
ask only whether that groundwork holds - and they are deliberately about the
shapes the rest of the migration will lean on rather than about Django.

See ../../../docs/python-migration.md.
"""

from django.test import TestCase

from school import factories, models


class TheSchemaIsDescribed(TestCase):
    def test_every_domain_table_has_a_model(self):
        # 32 domain models, matching the 32 Eloquent ones exactly, plus three
        # that are not domain tables:
        #
        #   personal_access_tokens - added at M8 so both backends can read the
        #   same signed-in session (school/tokens.py).
        #   queued_jobs - added at M9 for the work this backend defers, which
        #   Laravel's own `jobs` table cannot hold (see its migration).
        #   password_reset_tokens - added at M11 so a reset link either backend
        #   sends is one either backend honours (PasswordResetService).
        #
        # And six that exist only on this backend, added with Phase 19 after
        # the port: audit_logs, salary_profiles, salary_components,
        # payroll_runs, payslips and payslip_lines (docs/payroll.md). Laravel's
        # migrations still create them; Laravel has no models for them.
        #
        # And, from 2026-10-01, the assessments work (docs/assessments.md):
        # academic_terms, then grade_scales and grade_bands, then
        # student_enrollments (docs/promotion.md), then assessments and
        # assessment_marks.
        #
        # If this number moves again, either a table arrived without a model
        # or a model was invented for a table that is not there. Changing the
        # number is how that gets noticed; it should never be done to make a
        # test pass.
        from django.apps import apps

        self.assertEqual(54, len(list(apps.get_app_config("school").get_models())))

    def test_django_does_not_own_the_tables(self):
        # The whole reason check_models exists. If this ever passes with
        # managed=True outside a test run, Django has been given authority over
        # a schema Laravel is still migrating, and the two will diverge without
        # anybody noticing until a deploy.
        from django.apps import apps

        # Inside a test run the runner flips these deliberately, so the honest
        # assertion is about the source rather than the live attribute.
        with open(models.__file__, encoding="utf-8") as f:
            declarations = [line for line in f if line.strip() == "managed = False"]

        self.assertEqual(
            54,
            len(declarations),
            "every model must declare managed = False; the test runner is the only place that changes it",
        )


class TheFactoriesBuildASchool(TestCase):
    def test_a_standalone_school_has_no_parent(self):
        school = factories.SchoolFactory()

        self.assertIsNone(school.parent_school, "most schools are standalone")
        self.assertEqual("active", school.status)

    def test_a_group_is_a_parent_and_its_branches(self):
        # A branch is a school row with a parent and nothing else - the whole
        # multi-branch feature rests on that (docs/branches.md), so the
        # factories have to be able to say it in one line.
        group = factories.SchoolFactory(name="St Mary's Group")
        north = factories.SchoolFactory(name="St Mary's North", parent_school=group)
        south = factories.SchoolFactory(name="St Mary's South", parent_school=group)

        branches = models.School.objects.filter(parent_school=group).order_by("id")

        self.assertEqual([north.id, south.id], [b.id for b in branches])
        self.assertEqual(group.id, north.parent_school_id)

    def test_an_employee_gets_a_login_and_a_profile_in_the_same_school(self):
        staff = factories.StaffProfileFactory()

        self.assertEqual("TEACHER", staff.user.role)
        self.assertEqual(
            staff.school_id,
            staff.user.school_id,
            "the employment record and the login must agree about which school",
        )

    def test_a_student_lands_in_the_school_that_owns_their_section(self):
        # The relationship a rewrite is most likely to get subtly wrong: a
        # student's school_id has to follow the section, not be set separately.
        student = factories.StudentFactory()

        self.assertEqual(
            student.class_section.school_class.school_id,
            student.school_id,
            "a student's school must be the one that owns their class",
        )

    def test_a_whole_school_can_be_built_from_the_factories(self):
        group = factories.SchoolFactory(name="Group")
        branch = factories.SchoolFactory(name="Branch", parent_school=group)

        department = factories.DepartmentFactory(school=branch)
        factories.StaffProfileFactory(
            user=factories.UserFactory(school=branch, role="TEACHER"),
            school=branch,
            department=department,
        )

        year = factories.AcademicYearFactory(school=branch)
        school_class = factories.SchoolClassFactory(academic_year=year, school=branch)
        section = factories.ClassSectionFactory(school_class=school_class)

        students = [factories.StudentFactory(class_section=section, school=branch) for _ in range(3)]

        self.assertEqual(3, models.Student.objects.filter(school=branch).count())
        self.assertEqual(1, models.StaffProfile.objects.filter(school=branch).count())
        self.assertEqual(branch.id, students[0].school_id)
        self.assertEqual(group.id, branch.parent_school_id)


class TheStoredShapesAreRight(TestCase):
    def test_a_decimal_column_keeps_its_scale(self):
        # Money and coordinates are the two places a float would be wrong, and
        # the wrongness would not show up until somebody reconciled a ledger.
        school = factories.SchoolFactory(latitude="28.6139000", longitude="77.2090000")
        school.refresh_from_db()

        self.assertEqual("28.6139000", str(school.latitude))

    def test_timestamps_come_back_in_utc(self):
        # eduTrack stores instants in UTC and resolves each school's local day
        # in application code. A backend that localised on read would move
        # attendance across a day boundary (docs/timezones.md).
        school = factories.SchoolFactory()
        school.refresh_from_db()

        self.assertEqual("UTC", str(school.created_at.tzinfo))

<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\DailyTeachingReport;
use App\Models\Department;
use App\Models\Holiday;
use App\Models\Period;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffAttendance;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\Subject;
use App\Models\SyllabusTopic;
use App\Models\SyllabusTopicProgress;
use App\Models\TimetableEntry;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class HodDepartmentReportTest extends TestCase
{
    use RefreshDatabase;

    private const string ENDPOINT = '/api/v1/hod/department-report';

    /** A fixed past month so the fixture's dates never depend on "today". */
    private const string MONTH = '2026-08';

    /**
     * @return array{0: School, 1: Department, 2: User, 3: User, 4: StaffProfile}
     */
    private function makeDepartment(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->withHod($hod)->create();
        StaffProfile::factory()->forUser($hod)->forDepartment($department)->create();

        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create(['first_name' => 'Priya']);
        $teacherProfile = StaffProfile::factory()->forUser($teacher)->forDepartment($department)->create();

        return [$school, $department, $hod, $teacher, $teacherProfile];
    }

    private function makeSection(School $school): ClassSection
    {
        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($academicYear)->create();

        return ClassSection::factory()->forClass($schoolClass)->create();
    }

    private function makeEntry(School $school, ClassSection $section, Subject $subject, Period $period, User $teacher, string $day): TimetableEntry
    {
        return TimetableEntry::factory()
            ->forClassSection($section)
            ->forSubject($subject)
            ->forTeacher($teacher)
            ->forPeriod($period)
            ->onDay($day)
            ->create(['school_id' => $school->id]);
    }

    /**
     * August 2026 has 21 weekdays; Fri 14th and Mon 24th - Tue 25th are
     * holidays, leaving 18 working days. Priya is present (late) Mon 3rd,
     * half-day Tue 4th, absent Wed 5th, on leave Thu 6th; teaches Maths/8A
     * twice on Mondays, Science/9B on Tuesdays and Maths/8A on Wednesdays;
     * filed two reports on Mon 3rd (one reviewed); Maths has 4 topics
     * (2 done for 8A), Science has 2 (none done).
     *
     * @return array{0: School, 1: Department, 2: User, 3: User, 4: StaffProfile}
     */
    private function makeRichFixture(): array
    {
        [$school, $department, $hod, $teacher, $teacherProfile] = $this->makeDepartment();

        Holiday::factory()->forSchool($school)->onDates('2026-08-14')->create(['name' => 'Founders Day']);
        Holiday::factory()->forSchool($school)->onDates('2026-08-24', '2026-08-25')->type('vacation')->create();

        $period1 = Period::factory()->forSchool($school)->number(1)->create(['start_time' => '09:00', 'end_time' => '09:45']);
        $period2 = Period::factory()->forSchool($school)->number(2)->create(['start_time' => '09:45', 'end_time' => '10:30']);

        $sectionA = $this->makeSection($school);
        $sectionB = $this->makeSection($school);
        $maths = Subject::factory()->forDepartment($department)->create();
        $science = Subject::factory()->forDepartment($department)->create();

        $monday1 = $this->makeEntry($school, $sectionA, $maths, $period1, $teacher, 'monday');
        $monday2 = $this->makeEntry($school, $sectionA, $maths, $period2, $teacher, 'monday');
        $this->makeEntry($school, $sectionB, $science, $period1, $teacher, 'tuesday');
        $this->makeEntry($school, $sectionA, $maths, $period1, $teacher, 'wednesday');

        StaffAttendance::factory()->forStaff($teacherProfile)->onDate('2026-08-03')->status('present')->create(['check_in' => '09:15']);
        StaffAttendance::factory()->forStaff($teacherProfile)->onDate('2026-08-04')->status('half_day')->create(['check_in' => '08:50']);
        StaffAttendance::factory()->forStaff($teacherProfile)->onDate('2026-08-05')->status('absent')->create();
        StaffAttendance::factory()->forStaff($teacherProfile)->onDate('2026-08-06')->status('leave')->create();

        DailyTeachingReport::factory()->forEntry($monday1)->onDate('2026-08-03')->reviewed($hod->id)->create();
        DailyTeachingReport::factory()->forEntry($monday2)->onDate('2026-08-03')->create();

        // Thu-Fri (2 working days), Jul 30 - Sat Aug 1 (its only August day is a weekend: 0),
        // a half-day on a Monday (0.5), and a pending request that must not count.
        StaffLeave::factory()->forStaff($teacherProfile)->onDates('2026-08-06', '2026-08-07')->status('approved')->create();
        StaffLeave::factory()->forStaff($teacherProfile)->onDates('2026-07-30', '2026-08-01')->status('approved')->create();
        StaffLeave::factory()->forStaff($teacherProfile)->onDates('2026-08-10', '2026-08-10')->status('approved')->create(['leave_type' => 'half_day']);
        StaffLeave::factory()->forStaff($teacherProfile)->onDates('2026-08-12', '2026-08-14')->status('pending')->create();

        $mathsTopics = collect(range(1, 4))->map(
            fn (int $n) => SyllabusTopic::factory()->forSubject($maths)->atSequence($n)->create()
        );
        collect(range(1, 2))->each(fn (int $n) => SyllabusTopic::factory()->forSubject($science)->atSequence($n)->create());
        SyllabusTopicProgress::factory()->forTopic($mathsTopics[0])->forSection($sectionA)->completedBy($teacher)->create();
        SyllabusTopicProgress::factory()->forTopic($mathsTopics[1])->forSection($sectionA)->completedBy($teacher)->create();
        // Completed for a section Priya doesn't teach - must not count towards her syllabus %.
        SyllabusTopicProgress::factory()->forTopic($mathsTopics[2])->forSection($sectionB)->completedBy($hod)->create();

        return [$school, $department, $hod, $teacher, $teacherProfile];
    }

    private function teacherRow(array $json, int $userId): ?array
    {
        return collect($json['data'])->firstWhere('user_id', $userId);
    }

    // ── authorization: ALLOW ────────────────────────────────────────────

    public function test_an_hod_can_view_the_report_for_their_own_department(): void
    {
        [, $department, $hod, $teacher] = $this->makeDepartment();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $response->assertOk()
            ->assertJsonPath('month', self::MONTH)
            ->assertJsonPath('departments.0.id', $department->id)
            ->assertJsonPath('departments.0.name', $department->name);
        $this->assertNotNull($this->teacherRow($response->json(), $teacher->id));
    }

    public function test_an_hod_can_explicitly_request_their_own_department(): void
    {
        [, $department, $hod] = $this->makeDepartment();

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT."?department_id={$department->id}&month=".self::MONTH)
            ->assertOk()
            ->assertJsonPath('departments.0.id', $department->id);
    }

    public function test_a_school_admin_can_view_any_department_of_their_school(): void
    {
        [$school, $department, , $teacher] = $this->makeDepartment();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->getJson(self::ENDPOINT."?department_id={$department->id}&month=".self::MONTH);

        $response->assertOk()->assertJsonPath('teacher_count', 2);
        $this->assertNotNull($this->teacherRow($response->json(), $teacher->id));
    }

    public function test_a_school_admin_without_a_department_filter_sees_every_department(): void
    {
        [$school, $departmentA, , $teacherA] = $this->makeDepartment();
        [, $departmentB, , $teacherB] = $this->makeDepartment($school);
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $response->assertOk()->assertJsonCount(2, 'departments')->assertJsonPath('teacher_count', 4);
        $this->assertEqualsCanonicalizing(
            [$departmentA->id, $departmentB->id],
            collect($response->json('departments'))->pluck('id')->all()
        );
        $this->assertNotNull($this->teacherRow($response->json(), $teacherA->id));
        $this->assertNotNull($this->teacherRow($response->json(), $teacherB->id));
    }

    public function test_a_super_admin_can_view_a_report_for_any_school(): void
    {
        [$school, $department] = $this->makeDepartment();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson(self::ENDPOINT."?school_id={$school->id}&department_id={$department->id}&month=".self::MONTH)
            ->assertOk()
            ->assertJsonPath('school_id', $school->id);
    }

    public function test_the_month_defaults_to_the_current_month(): void
    {
        [, , $hod] = $this->makeDepartment();

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT)
            ->assertOk()
            ->assertJsonPath('month', now()->format('Y-m'));
    }

    // ── authorization: DENY ─────────────────────────────────────────────

    public function test_an_hod_cannot_view_another_departments_report(): void
    {
        [$school, , $hod] = $this->makeDepartment();
        [, $otherDepartment] = $this->makeDepartment($school);

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT."?department_id={$otherDepartment->id}&month=".self::MONTH)
            ->assertForbidden();
    }

    public function test_an_hod_without_a_filter_only_sees_teachers_of_departments_they_head(): void
    {
        [$school, $department, $hod, $teacher] = $this->makeDepartment();
        [, , , $otherTeacher] = $this->makeDepartment($school);

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $response->assertOk()->assertJsonCount(1, 'departments')->assertJsonPath('departments.0.id', $department->id);
        $this->assertNotNull($this->teacherRow($response->json(), $teacher->id));
        $this->assertNull($this->teacherRow($response->json(), $otherTeacher->id));
    }

    public function test_an_hod_heading_two_departments_sees_both(): void
    {
        [$school, $departmentA, $hod, $teacherA] = $this->makeDepartment();
        $departmentB = Department::factory()->forSchool($school)->withHod($hod)->create();
        $teacherB = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        StaffProfile::factory()->forUser($teacherB)->forDepartment($departmentB)->create();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $response->assertOk()->assertJsonCount(2, 'departments');
        $this->assertEqualsCanonicalizing(
            [$departmentA->id, $departmentB->id],
            collect($response->json('departments'))->pluck('id')->all()
        );
        $this->assertNotNull($this->teacherRow($response->json(), $teacherA->id));
        $this->assertNotNull($this->teacherRow($response->json(), $teacherB->id));
    }

    public function test_a_school_admin_cannot_request_a_department_of_another_school(): void
    {
        [$school] = $this->makeDepartment();
        [, $foreignDepartment] = $this->makeDepartment();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->getJson(self::ENDPOINT."?department_id={$foreignDepartment->id}&month=".self::MONTH)
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['department_id']]]);
    }

    public function test_a_school_admin_never_sees_another_schools_teachers(): void
    {
        [$school] = $this->makeDepartment();
        [, , , $foreignTeacher] = $this->makeDepartment();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $response->assertOk();
        $this->assertNull($this->teacherRow($response->json(), $foreignTeacher->id));
    }

    public function test_a_super_admin_must_supply_a_school(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson(self::ENDPOINT.'?month='.self::MONTH)
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['school_id']]]);
    }

    public function test_a_teacher_cannot_view_the_report(): void
    {
        [, , , $teacher] = $this->makeDepartment();

        $this->actingAs($teacher, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH)->assertForbidden();
    }

    public function test_staff_and_transport_manager_roles_cannot_view_the_report(): void
    {
        [$school] = $this->makeDepartment();

        foreach ([UserRole::Staff, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH)->assertForbidden();
        }
    }

    public function test_an_unauthenticated_request_is_rejected(): void
    {
        $this->getJson(self::ENDPOINT)->assertUnauthorized();
    }

    // ── validation ──────────────────────────────────────────────────────

    public function test_the_month_must_be_in_year_month_format(): void
    {
        [, , $hod] = $this->makeDepartment();

        foreach (['2026', '2026-13', '08-2026', '2026-08-01', 'august'] as $bad) {
            $this->actingAs($hod, 'sanctum')
                ->getJson(self::ENDPOINT."?month={$bad}")
                ->assertUnprocessable()
                ->assertJsonStructure(['details' => ['errors' => ['month']]]);
        }
    }

    public function test_an_unknown_department_id_is_rejected(): void
    {
        [, , $hod] = $this->makeDepartment();

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT.'?department_id=999999&month='.self::MONTH)
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['department_id']]]);
    }

    // ── calculations ────────────────────────────────────────────────────

    public function test_it_computes_every_metric_for_a_teacher(): void
    {
        [, , $hod, $teacher, $teacherProfile] = $this->makeRichFixture();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $response->assertOk()->assertJsonPath('working_days', 18);
        $row = $this->teacherRow($response->json(), $teacher->id);

        $this->assertSame($teacherProfile->id, $row['staff_profile_id']);
        $this->assertSame($teacher->name, $row['teacher_name']);
        $this->assertSame($teacherProfile->employee_id, $row['employee_id']);
        $this->assertSame(8.3, $row['attendance_percent']);    // (1 present + 0.5 half-day) / 18 working days
        $this->assertSame(2.5, $row['leave_days']);            // Thu+Fri + 0.5 half-day; Sat and pending ignored
        $this->assertSame(1, $row['late_marks']);              // 09:15 check-in vs 09:00 first period
        $this->assertSame(15, $row['classes_assigned']);       // Mon 4x2 (24th is a holiday) + Tue 3 (25th) + Wed 4
        $this->assertSame(3, $row['classes_taught']);          // present Mon 3rd (2) + half-day Tue 4th (1)
        $this->assertSame(2, $row['reports_submitted']);
        $this->assertSame(1, $row['reports_pending_review']);
        $this->assertSame(33, $row['syllabus_percent']);       // 2 of (4 maths + 2 science) topics
        $this->assertSame('review', $row['status']);
    }

    public function test_it_computes_department_wide_kpis_across_every_teacher_in_scope(): void
    {
        [, , $hod] = $this->makeRichFixture();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        // Priya (1.5 credits) + the HOD (no attendance) over 18 days x 2 teachers.
        $response->assertOk()
            ->assertJsonPath('teacher_count', 2)
            ->assertJsonPath('working_days', 18)
            ->assertJsonPath('avg_attendance_percent', 4.2)
            ->assertJsonPath('leave_days', 2.5)
            ->assertJsonPath('late_marks', 1);
    }

    public function test_a_teacher_with_no_activity_is_on_track_with_zero_metrics(): void
    {
        [, , $hod] = $this->makeRichFixture();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);
        $row = $this->teacherRow($response->json(), $hod->id);

        $this->assertEquals(0, $row['attendance_percent']);
        $this->assertSame(0, $row['classes_assigned']);
        $this->assertSame(0, $row['classes_taught']);
        $this->assertSame(0, $row['reports_submitted']);
        $this->assertSame(0, $row['syllabus_percent']);
        $this->assertSame('on_track', $row['status']);
    }

    public function test_a_teacher_is_on_track_when_every_taught_class_is_reported_and_reviewed(): void
    {
        [$school, $department, $hod, $teacher, $teacherProfile] = $this->makeDepartment();
        $period = Period::factory()->forSchool($school)->number(1)->create();
        $entry = $this->makeEntry($school, $this->makeSection($school), Subject::factory()->forDepartment($department)->create(), $period, $teacher, 'monday');
        StaffAttendance::factory()->forStaff($teacherProfile)->onDate('2026-08-03')->status('present')->create();
        DailyTeachingReport::factory()->forEntry($entry)->onDate('2026-08-03')->reviewed($hod->id)->create();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);
        $row = $this->teacherRow($response->json(), $teacher->id);

        $this->assertSame(1, $row['classes_taught']);
        $this->assertSame(1, $row['reports_submitted']);
        $this->assertSame(0, $row['reports_pending_review']);
        $this->assertSame('on_track', $row['status']);
    }

    public function test_a_month_that_is_entirely_a_vacation_yields_zero_working_days_and_no_division_errors(): void
    {
        [$school, , $hod, $teacher] = $this->makeRichFixture();
        Holiday::factory()->forSchool($school)->onDates('2026-05-01', '2026-05-31')->type('vacation')->create();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month=2026-05');

        $response->assertOk()
            ->assertJsonPath('working_days', 0)
            ->assertJsonPath('avg_attendance_percent', 0)
            ->assertJsonPath('late_marks', 0)
            ->assertJsonPath('leave_days', 0);
        $row = $this->teacherRow($response->json(), $teacher->id);
        $this->assertEquals(0, $row['attendance_percent']);
        $this->assertSame(0, $row['classes_assigned']);
        $this->assertSame(0, $row['classes_taught']);
    }

    public function test_working_days_are_weekdays_minus_holidays(): void
    {
        [$school, , $hod] = $this->makeDepartment();
        // May 2026 has 21 weekdays; Fri 1st is a holiday, and a Sat-Sun break must not change anything.
        Holiday::factory()->forSchool($school)->onDates('2026-05-01')->create();
        Holiday::factory()->forSchool($school)->onDates('2026-05-09', '2026-05-10')->create();

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT.'?month=2026-05')
            ->assertOk()
            ->assertJsonPath('working_days', 20);
    }

    public function test_the_current_month_only_counts_working_days_up_to_today(): void
    {
        [, , $hod] = $this->makeDepartment();
        $expected = 0;
        for ($date = now()->startOfMonth(); $date->lte(now()->startOfDay()); $date->addDay()) {
            if (! $date->isWeekend()) {
                $expected++;
            }
        }

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT.'?month='.now()->format('Y-m'))
            ->assertOk()
            ->assertJsonPath('working_days', $expected);
    }

    public function test_a_shorter_month_asked_for_late_in_a_month_is_still_that_month(): void
    {
        // Asked for on March 30th, February must not overflow into March.
        // February 2026 has 20 weekdays; March up to the 30th has 21.
        $this->travelTo('2026-03-30 10:00:00');
        [, , $hod] = $this->makeDepartment();

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT.'?month=2026-02')
            ->assertOk()
            ->assertJsonPath('month', '2026-02')
            ->assertJsonPath('working_days', 20);
    }

    public function test_today_at_a_school_east_of_utc_counts_as_a_working_day(): void
    {
        // 20:00 UTC on Tue 15 September is already Wed 16th in Kolkata, so the
        // school has reached twelve working days. Comparing instants across
        // the two zones used to stop at the 15th and answer eleven.
        $this->travelTo(Carbon::parse('2026-09-15 20:00:00', 'UTC'));
        [, , $hod] = $this->makeDepartment(School::factory()->create(['timezone' => 'Asia/Kolkata']));

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT.'?month=2026-09')
            ->assertOk()
            ->assertJsonPath('working_days', 12);
    }

    public function test_a_future_month_has_no_working_days_yet(): void
    {
        [, , $hod] = $this->makeDepartment();

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT.'?month='.now()->addMonths(2)->format('Y-m'))
            ->assertOk()
            ->assertJsonPath('working_days', 0);
    }

    public function test_late_marks_are_zero_when_the_school_has_no_periods_defined(): void
    {
        [, , $hod, $teacher, $teacherProfile] = $this->makeDepartment();
        StaffAttendance::factory()->forStaff($teacherProfile)->onDate('2026-08-03')->status('present')->create(['check_in' => '11:30']);

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $response->assertOk()->assertJsonPath('late_marks', 0);
        $this->assertSame(0, $this->teacherRow($response->json(), $teacher->id)['late_marks']);
    }

    public function test_another_schools_holidays_do_not_reduce_this_schools_working_days(): void
    {
        [, , $hod] = $this->makeDepartment();
        [$otherSchool] = $this->makeDepartment();
        Holiday::factory()->forSchool($otherSchool)->onDates('2026-08-03', '2026-08-07')->type('vacation')->create();

        $this->actingAs($hod, 'sanctum')
            ->getJson(self::ENDPOINT.'?month='.self::MONTH)
            ->assertOk()
            ->assertJsonPath('working_days', 21);
    }

    // ── row membership ──────────────────────────────────────────────────

    public function test_inactive_teachers_and_non_teaching_roles_are_excluded(): void
    {
        [$school, $department, $hod] = $this->makeDepartment();
        $inactive = User::factory()->role(UserRole::Teacher)->forSchool($school)->create(['status' => UserStatus::Inactive]);
        StaffProfile::factory()->forUser($inactive)->forDepartment($department)->create();
        $clerk = User::factory()->role(UserRole::Staff)->forSchool($school)->create();
        StaffProfile::factory()->forUser($clerk)->forDepartment($department)->create();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $response->assertOk()->assertJsonPath('teacher_count', 2);
        $this->assertNull($this->teacherRow($response->json(), $inactive->id));
        $this->assertNull($this->teacherRow($response->json(), $clerk->id));
    }

    public function test_the_hod_appears_as_a_row_in_their_own_department(): void
    {
        [, $department, $hod] = $this->makeDepartment();

        $response = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?month='.self::MONTH);

        $row = $this->teacherRow($response->json(), $hod->id);
        $this->assertNotNull($row);
        $this->assertSame($department->name, $row['department_name']);
    }

    public function test_rows_are_ordered_by_first_name_and_paginated(): void
    {
        [$school, $department, $hod] = $this->makeDepartment();
        $hod->update(['first_name' => 'Zara']);
        $anil = User::factory()->role(UserRole::Teacher)->forSchool($school)->create(['first_name' => 'Anil']);
        StaffProfile::factory()->forUser($anil)->forDepartment($department)->create();

        $firstPage = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?per_page=2&month='.self::MONTH);

        $firstPage->assertOk()
            ->assertJsonPath('meta.total', 3)
            ->assertJsonPath('meta.per_page', 2)
            ->assertJsonPath('meta.last_page', 2)
            ->assertJsonCount(2, 'data')
            ->assertJsonPath('data.0.teacher_name', $anil->name)
            ->assertJsonPath('teacher_count', 3);

        $secondPage = $this->actingAs($hod, 'sanctum')->getJson(self::ENDPOINT.'?per_page=2&page=2&month='.self::MONTH);

        $secondPage->assertOk()->assertJsonCount(1, 'data')->assertJsonPath('data.0.user_id', $hod->id);
    }
}

<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\DailyTeachingReport;
use App\Models\Department;
use App\Models\Period;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffProfile;
use App\Models\Subject;
use App\Models\TimetableEntry;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class DailyTeachingReportManagementTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array{0: School, 1: Department, 2: User, 3: StaffProfile, 4: User, 5: StaffProfile, 6: TimetableEntry}
     */
    private function makeFixtures(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $hodUser = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->withHod($hodUser)->create();
        $hodProfile = StaffProfile::factory()->forUser($hodUser)->forDepartment($department)->create();

        $teacherUser = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $teacherProfile = StaffProfile::factory()->forUser($teacherUser)->forDepartment($department)->create();

        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($academicYear)->create();
        $classSection = ClassSection::factory()->forClass($schoolClass)->create();
        $subject = Subject::factory()->forDepartment($department)->create();
        $period = Period::factory()->forSchool($school)->create();

        $entry = TimetableEntry::factory()
            ->forClassSection($classSection)
            ->forSubject($subject)
            ->forTeacher($teacherUser)
            ->forPeriod($period)
            ->onDay('monday')
            ->create(['school_id' => $school->id]);

        return [$school, $department, $hodUser, $hodProfile, $teacherUser, $teacherProfile, $entry];
    }

    private function pastMonday(): string
    {
        return Carbon::now()->startOfWeek(Carbon::MONDAY)->subWeek()->toDateString();
    }

    private function reportPayload(TimetableEntry $entry, array $overrides = []): array
    {
        return array_merge([
            'timetable_entry_id' => $entry->id,
            'report_date' => $this->pastMonday(),
            'topic_taught' => 'Photosynthesis basics',
            'homework' => 'Read chapter 4',
            'remarks' => null,
        ], $overrides);
    }

    // ── submit (create) ─────────────────────────────────────────────────

    public function test_a_teacher_can_submit_a_report_for_their_scheduled_period(): void
    {
        [$school, , , , $teacherUser, , $entry] = $this->makeFixtures();

        $response = $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry));

        $response->assertCreated()
            ->assertJsonPath('topic_taught', 'Photosynthesis basics')
            ->assertJsonPath('teacher_name', $teacherUser->name);
        $this->assertDatabaseHas('daily_teaching_reports', [
            'school_id' => $school->id,
            'timetable_entry_id' => $entry->id,
            'teacher_id' => $teacherUser->id,
        ]);
    }

    public function test_an_hod_can_submit_a_report_for_a_period_they_are_scheduled_to_teach(): void
    {
        [$school, $department, $hodUser] = $this->makeFixtures();
        $section = ClassSection::factory()->forClass(
            SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create()
        )->create();
        $subject = Subject::factory()->forDepartment($department)->create();
        $period = Period::factory()->forSchool($school)->create();
        $entry = TimetableEntry::factory()->forClassSection($section)->forSubject($subject)
            ->forTeacher($hodUser)->forPeriod($period)->onDay('monday')->create(['school_id' => $school->id]);

        $this->actingAs($hodUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry))
            ->assertCreated();
    }

    public function test_a_teacher_cannot_submit_a_report_for_a_period_they_are_not_assigned_to(): void
    {
        [, , , , , , $entry] = $this->makeFixtures();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool($entry->school)->create();

        $this->actingAs($otherTeacher, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry))
            ->assertForbidden();
    }

    public function test_a_school_admin_cannot_submit_a_teaching_report(): void
    {
        [$school, , , , , , $entry] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry))
            ->assertForbidden();
    }

    public function test_a_staff_role_cannot_submit_a_teaching_report(): void
    {
        [$school, , , , , , $entry] = $this->makeFixtures();
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();

        $this->actingAs($staff, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry))
            ->assertForbidden();
    }

    public function test_report_date_must_match_the_periods_scheduled_day_of_week(): void
    {
        [, , , , $teacherUser, , $entry] = $this->makeFixtures();
        $tuesday = Carbon::parse($this->pastMonday())->addDay()->toDateString();

        $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry, ['report_date' => $tuesday]))
            ->assertUnprocessable();
    }

    public function test_a_future_report_date_is_rejected(): void
    {
        [, , , , $teacherUser, , $entry] = $this->makeFixtures();

        $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry, [
                'report_date' => now()->addWeek()->toDateString(),
            ]))
            ->assertUnprocessable();
    }

    public function test_submitting_a_duplicate_report_for_the_same_period_and_date_is_rejected(): void
    {
        [, , , , $teacherUser, , $entry] = $this->makeFixtures();
        $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry))
            ->assertCreated();

        $response = $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry));

        $response->assertConflict()->assertJsonPath('code', 'TEACHING_REPORT_ALREADY_SUBMITTED');
        $this->assertDatabaseCount('daily_teaching_reports', 1);
    }

    public function test_topic_taught_is_required(): void
    {
        [, , , , $teacherUser, , $entry] = $this->makeFixtures();

        $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry, ['topic_taught' => '']))
            ->assertUnprocessable();
    }

    public function test_a_nonexistent_timetable_entry_id_is_rejected(): void
    {
        [, , , , $teacherUser, , $entry] = $this->makeFixtures();

        $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry, ['timetable_entry_id' => 999999]))
            ->assertUnprocessable();
    }

    public function test_homework_and_remarks_exceeding_the_max_length_are_rejected(): void
    {
        [, , , , $teacherUser, , $entry] = $this->makeFixtures();

        $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry, ['homework' => str_repeat('a', 501)]))
            ->assertUnprocessable();

        $this->actingAs($teacherUser, 'sanctum')
            ->postJson('/api/v1/teaching-reports', $this->reportPayload($entry, ['remarks' => str_repeat('a', 501)]))
            ->assertUnprocessable();
    }

    // ── review ───────────────────────────────────────────────────────────

    public function test_an_hod_can_review_a_teachers_report_in_their_department(): void
    {
        [, , $hodUser, , $teacherUser, , $entry] = $this->makeFixtures();
        $report = DailyTeachingReport::factory()->forEntry($entry)->create();

        $response = $this->actingAs($hodUser, 'sanctum')->patchJson("/api/v1/teaching-reports/{$report->id}/review");

        $response->assertOk()->assertJsonPath('reviewed_by_name', $hodUser->name);
        $this->assertNotNull($report->fresh()->reviewed_at);
    }

    public function test_a_school_admin_can_review_any_report_in_their_school(): void
    {
        [$school, , , , , , $entry] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $report = DailyTeachingReport::factory()->forEntry($entry)->create();

        $this->actingAs($admin, 'sanctum')->patchJson("/api/v1/teaching-reports/{$report->id}/review")
            ->assertOk();
    }

    public function test_a_super_admin_can_review_any_report(): void
    {
        [, , , , , , $entry] = $this->makeFixtures();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $report = DailyTeachingReport::factory()->forEntry($entry)->create();

        $this->actingAs($superAdmin, 'sanctum')->patchJson("/api/v1/teaching-reports/{$report->id}/review")
            ->assertOk();
    }

    public function test_a_teacher_cannot_review_their_own_report(): void
    {
        [, , , , $teacherUser, , $entry] = $this->makeFixtures();
        $report = DailyTeachingReport::factory()->forEntry($entry)->create();

        $this->actingAs($teacherUser, 'sanctum')->patchJson("/api/v1/teaching-reports/{$report->id}/review")
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_review_someone_elses_report(): void
    {
        [$school, , , , , , $entry] = $this->makeFixtures();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $report = DailyTeachingReport::factory()->forEntry($entry)->create();

        $this->actingAs($otherTeacher, 'sanctum')->patchJson("/api/v1/teaching-reports/{$report->id}/review")
            ->assertForbidden();
    }

    public function test_an_hod_cannot_review_a_report_outside_their_department(): void
    {
        [$school, , $hodUser] = $this->makeFixtures();
        $otherDepartment = Department::factory()->forSchool($school)->create();
        $outsiderTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        StaffProfile::factory()->forUser($outsiderTeacher)->forDepartment($otherDepartment)->create();
        $section = ClassSection::factory()->forClass(
            SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create()
        )->create();
        $subject = Subject::factory()->forDepartment($otherDepartment)->create();
        $period = Period::factory()->forSchool($school)->create();
        $outsiderEntry = TimetableEntry::factory()->forClassSection($section)->forSubject($subject)
            ->forTeacher($outsiderTeacher)->forPeriod($period)->onDay('monday')->create(['school_id' => $school->id]);
        $report = DailyTeachingReport::factory()->forEntry($outsiderEntry)->create();

        $this->actingAs($hodUser, 'sanctum')->patchJson("/api/v1/teaching-reports/{$report->id}/review")
            ->assertForbidden();
    }

    public function test_a_school_admin_cannot_review_a_report_from_another_school(): void
    {
        [, , , , , , $entry] = $this->makeFixtures();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();
        $report = DailyTeachingReport::factory()->forEntry($entry)->create();

        $this->actingAs($otherAdmin, 'sanctum')->patchJson("/api/v1/teaching-reports/{$report->id}/review")
            ->assertForbidden();
    }

    public function test_reviewing_an_already_reviewed_report_is_rejected(): void
    {
        [, , $hodUser, , , , $entry] = $this->makeFixtures();
        $report = DailyTeachingReport::factory()->forEntry($entry)->reviewed($hodUser->id)->create();

        $this->actingAs($hodUser, 'sanctum')->patchJson("/api/v1/teaching-reports/{$report->id}/review")
            ->assertConflict()
            ->assertJsonPath('code', 'TEACHING_REPORT_ALREADY_REVIEWED');
    }

    // ── index / visibility scoping ───────────────────────────────────────

    public function test_a_teacher_only_sees_their_own_reports(): void
    {
        [$school, $department, , , $teacherUser, , $entry] = $this->makeFixtures();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        StaffProfile::factory()->forUser($otherTeacher)->forDepartment($department)->create();
        $otherEntry = TimetableEntry::factory()->forClassSection($entry->classSection)->forSubject($entry->subject)
            ->forTeacher($otherTeacher)->forPeriod(Period::factory()->forSchool($school)->create())
            ->onDay('monday')->create(['school_id' => $school->id]);
        DailyTeachingReport::factory()->forEntry($entry)->create();
        DailyTeachingReport::factory()->forEntry($otherEntry)->create();

        $this->actingAs($teacherUser, 'sanctum')->getJson('/api/v1/teaching-reports')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    public function test_an_hod_sees_reports_for_their_whole_department(): void
    {
        [$school, , $hodUser, $hodProfile, , , $entry] = $this->makeFixtures();
        $hodEntry = TimetableEntry::factory()->forClassSection($entry->classSection)->forSubject($entry->subject)
            ->forTeacher($hodUser)->forPeriod(Period::factory()->forSchool($school)->create())
            ->onDay('monday')->create(['school_id' => $school->id]);
        DailyTeachingReport::factory()->forEntry($entry)->create();
        DailyTeachingReport::factory()->forEntry($hodEntry)->create();

        $this->actingAs($hodUser, 'sanctum')->getJson('/api/v1/teaching-reports')
            ->assertOk()
            ->assertJsonCount(2, 'data');
    }

    public function test_a_school_admin_sees_only_their_schools_reports(): void
    {
        [$schoolA, , , , , , $entryA] = $this->makeFixtures();
        [$schoolB, , , , , , $entryB] = $this->makeFixtures();
        DailyTeachingReport::factory()->forEntry($entryA)->create();
        DailyTeachingReport::factory()->forEntry($entryB)->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/teaching-reports')
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    public function test_a_staff_role_cannot_view_teaching_reports(): void
    {
        [$school] = $this->makeFixtures();
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();

        $this->actingAs($staff, 'sanctum')->getJson('/api/v1/teaching-reports')->assertForbidden();
    }

    public function test_a_transport_manager_cannot_view_teaching_reports(): void
    {
        [$school] = $this->makeFixtures();
        $transportManager = User::factory()->role(UserRole::TransportManager)->forSchool($school)->create();

        $this->actingAs($transportManager, 'sanctum')->getJson('/api/v1/teaching-reports')->assertForbidden();
    }

    // ── summary ──────────────────────────────────────────────────────────

    public function test_the_summary_counts_scheduled_submitted_and_pending(): void
    {
        [$school, $department, , , $teacherUser, , $entry] = $this->makeFixtures();
        $secondPeriod = Period::factory()->forSchool($school)->number($entry->period->period_number + 1)->create();
        TimetableEntry::factory()->forClassSection($entry->classSection)->forSubject($entry->subject)
            ->forTeacher($teacherUser)->forPeriod($secondPeriod)->onDay('monday')
            ->create(['school_id' => $school->id]);
        DailyTeachingReport::factory()->forEntry($entry)->onDate($this->pastMonday())->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->getJson('/api/v1/teaching-reports/summary?date='.$this->pastMonday());

        $response->assertOk()
            ->assertJsonPath('scheduled', 2)
            ->assertJsonPath('submitted', 1)
            ->assertJsonPath('pending', 1);
    }

    public function test_the_summary_requires_a_date_query_param(): void
    {
        [$school] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/teaching-reports/summary')->assertUnprocessable();
    }
}

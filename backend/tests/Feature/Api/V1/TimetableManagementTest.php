<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\Department;
use App\Models\Period;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\Subject;
use App\Models\TimetableEntry;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TimetableManagementTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array{0: School, 1: ClassSection, 2: Subject, 3: User, 4: Period}
     */
    private function makeFixtures(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($academicYear)->create();
        $classSection = ClassSection::factory()->forClass($schoolClass)->create();
        $department = Department::factory()->forSchool($school)->create();
        $subject = Subject::factory()->forDepartment($department)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $period = Period::factory()->forSchool($school)->create();

        return [$school, $classSection, $subject, $teacher, $period];
    }

    private function entryPayload(ClassSection $classSection, Subject $subject, User $teacher, Period $period, array $overrides = []): array
    {
        return array_merge([
            'class_section_id' => $classSection->id,
            'period_id' => $period->id,
            'day_of_week' => 'monday',
            'subject_id' => $subject->id,
            'teacher_id' => $teacher->id,
        ], $overrides);
    }

    // ── grid (view) ──────────────────────────────────────────────────────

    public function test_a_teacher_can_view_a_class_sections_grid(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        TimetableEntry::factory()->forClassSection($classSection)->forSubject($subject)->forTeacher($teacher)->forPeriod($period)->create(['school_id' => $school->id]);
        $viewer = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $response = $this->actingAs($viewer, 'sanctum')->getJson("/api/v1/timetable?class_section_id={$classSection->id}");

        $response->assertOk();
        $this->assertCount(1, $response->json());
        $response->assertJsonPath('0.day_of_week', 'monday');
    }

    public function test_a_teacher_can_view_their_own_schedule_across_class_sections(): void
    {
        [$school, , $subject, $teacher, $period] = $this->makeFixtures();
        $secondSection = ClassSection::factory()->create([
            'school_class_id' => SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create()),
        ]);
        $otherPeriod = Period::factory()->forSchool($school)->number($period->period_number + 1)->create();
        TimetableEntry::factory()->forClassSection($secondSection)->forSubject($subject)->forTeacher($teacher)->forPeriod($otherPeriod)->create(['school_id' => $school->id]);

        $response = $this->actingAs($teacher, 'sanctum')->getJson("/api/v1/timetable?teacher_id={$teacher->id}");

        $response->assertOk();
        $this->assertCount(1, $response->json());
    }

    public function test_viewing_a_class_section_from_another_school_is_rejected(): void
    {
        [, $classSection] = $this->makeFixtures();
        $otherSchoolViewer = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherSchoolViewer, 'sanctum')
            ->getJson("/api/v1/timetable?class_section_id={$classSection->id}")
            ->assertNotFound();
    }

    public function test_a_super_admin_can_view_any_schools_grid(): void
    {
        [, $classSection] = $this->makeFixtures();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson("/api/v1/timetable?class_section_id={$classSection->id}")
            ->assertOk();
    }

    public function test_requesting_the_grid_without_a_class_section_or_teacher_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->getJson('/api/v1/timetable')->assertUnprocessable();
    }

    // ── upsert (create/replace a cell) ──────────────────────────────────

    public function test_a_school_admin_can_create_a_timetable_entry(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $teacher, $period));

        $response->assertCreated()->assertJsonPath('subject_name', $subject->name);
        $this->assertDatabaseCount('timetable_entries', 1);
    }

    public function test_a_super_admin_can_create_a_timetable_entry_for_any_school(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/v1/timetable', [
                ...$this->entryPayload($classSection, $subject, $teacher, $period),
                'school_id' => $school->id,
            ])
            ->assertCreated();
    }

    public function test_a_teacher_cannot_create_a_timetable_entry(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($otherTeacher, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $teacher, $period))
            ->assertForbidden();
    }

    public function test_an_hod_cannot_create_a_timetable_entry(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();

        $this->actingAs($hod, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $teacher, $period))
            ->assertForbidden();
    }

    public function test_submitting_the_same_cell_again_replaces_the_entry_instead_of_duplicating(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $otherSubject = Subject::factory()->forDepartment(Department::factory()->forSchool($school)->create())->create();
        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $teacher, $period))
            ->assertCreated();

        $response = $this->actingAs($admin, 'sanctum')->postJson(
            '/api/v1/timetable',
            $this->entryPayload($classSection, $otherSubject, $teacher, $period)
        );

        $response->assertCreated()->assertJsonPath('subject_name', $otherSubject->name);
        $this->assertDatabaseCount('timetable_entries', 1);
    }

    public function test_a_teacher_double_booked_across_two_class_sections_is_rejected(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $teacher, $period))
            ->assertCreated();
        $secondSection = ClassSection::factory()->create([
            'school_class_id' => SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create()),
        ]);

        $response = $this->actingAs($admin, 'sanctum')->postJson(
            '/api/v1/timetable',
            $this->entryPayload($secondSection, $subject, $teacher, $period)
        );

        $response->assertConflict()->assertJsonPath('code', 'TEACHER_SCHEDULE_CONFLICT');
        $this->assertDatabaseCount('timetable_entries', 1);
    }

    public function test_the_same_teacher_in_the_same_period_on_a_different_day_is_allowed(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $secondSection = ClassSection::factory()->create([
            'school_class_id' => SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create()),
        ]);
        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $teacher, $period, ['day_of_week' => 'monday']))
            ->assertCreated();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($secondSection, $subject, $teacher, $period, ['day_of_week' => 'tuesday']))
            ->assertCreated();
    }

    public function test_a_class_section_from_another_school_is_rejected(): void
    {
        [$school, , $subject, $teacher, $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $otherSection = ClassSection::factory()->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($otherSection, $subject, $teacher, $period))
            ->assertUnprocessable();
    }

    public function test_a_teacher_from_another_school_is_rejected(): void
    {
        [$school, $classSection, $subject, , $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool(School::factory()->create())->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $otherTeacher, $period))
            ->assertUnprocessable();
    }

    public function test_a_non_teaching_role_cannot_be_assigned_as_the_teacher(): void
    {
        [$school, $classSection, $subject, , $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $staff, $period))
            ->assertUnprocessable();
    }

    public function test_an_invalid_day_of_week_is_rejected(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/timetable', $this->entryPayload($classSection, $subject, $teacher, $period, ['day_of_week' => 'sunday']))
            ->assertUnprocessable();
    }

    // ── delete ───────────────────────────────────────────────────────────

    public function test_a_school_admin_can_delete_a_timetable_entry(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $entry = TimetableEntry::factory()->forClassSection($classSection)->forSubject($subject)->forTeacher($teacher)->forPeriod($period)->create(['school_id' => $school->id]);

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/timetable/{$entry->id}")->assertNoContent();
        $this->assertDatabaseMissing('timetable_entries', ['id' => $entry->id]);
    }

    public function test_a_teacher_cannot_delete_a_timetable_entry(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $entry = TimetableEntry::factory()->forClassSection($classSection)->forSubject($subject)->forTeacher($teacher)->forPeriod($period)->create(['school_id' => $school->id]);

        $this->actingAs($teacher, 'sanctum')->deleteJson("/api/v1/timetable/{$entry->id}")->assertForbidden();
    }

    public function test_a_school_admin_cannot_delete_another_schools_entry(): void
    {
        [$school, $classSection, $subject, $teacher, $period] = $this->makeFixtures();
        $entry = TimetableEntry::factory()->forClassSection($classSection)->forSubject($subject)->forTeacher($teacher)->forPeriod($period)->create(['school_id' => $school->id]);
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherAdmin, 'sanctum')->deleteJson("/api/v1/timetable/{$entry->id}")->assertForbidden();
    }
}

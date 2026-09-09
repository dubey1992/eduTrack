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
use App\Models\SyllabusTopic;
use App\Models\SyllabusTopicProgress;
use App\Models\TimetableEntry;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SyllabusProgressManagementTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array{0: School, 1: Department, 2: User, 3: Subject, 4: User, 5: ClassSection, 6: SyllabusTopic}
     */
    private function makeFixtures(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->withHod($hod)->create();
        $subject = Subject::factory()->forDepartment($department)->create();

        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($academicYear)->create();
        $classSection = ClassSection::factory()->forClass($schoolClass)->create();
        $period = Period::factory()->forSchool($school)->create();

        TimetableEntry::factory()->forClassSection($classSection)->forSubject($subject)
            ->forTeacher($teacher)->forPeriod($period)->onDay('monday')->create(['school_id' => $school->id]);

        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();

        return [$school, $department, $hod, $subject, $teacher, $classSection, $topic];
    }

    private function togglePayload(SyllabusTopic $topic, ClassSection $section, bool $completed = true): array
    {
        return [
            'syllabus_topic_id' => $topic->id,
            'class_section_id' => $section->id,
            'completed' => $completed,
        ];
    }

    // ── mark (toggle) ────────────────────────────────────────────────────

    public function test_the_teacher_scheduled_for_the_subject_and_section_can_mark_a_topic_complete(): void
    {
        [, , , , $teacher, $section, $topic] = $this->makeFixtures();

        $response = $this->actingAs($teacher, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section));

        $response->assertOk()->assertJsonPath('completed_topics', 1)->assertJsonPath('total_topics', 1);
        $this->assertDatabaseHas('syllabus_topic_progress', [
            'syllabus_topic_id' => $topic->id, 'class_section_id' => $section->id, 'completed_by' => $teacher->id,
        ]);
    }

    public function test_marking_a_topic_incomplete_removes_the_progress_row(): void
    {
        [, , , , $teacher, $section, $topic] = $this->makeFixtures();
        $this->actingAs($teacher, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section, true))
            ->assertOk();

        $response = $this->actingAs($teacher, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section, false));

        $response->assertOk()->assertJsonPath('completed_topics', 0);
        $this->assertDatabaseMissing('syllabus_topic_progress', [
            'syllabus_topic_id' => $topic->id, 'class_section_id' => $section->id,
        ]);
    }

    public function test_a_teacher_not_scheduled_for_that_subject_and_section_cannot_mark_it(): void
    {
        [$school, , , , , $section, $topic] = $this->makeFixtures();
        $otherTeacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($otherTeacher, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section))
            ->assertForbidden();
    }

    public function test_the_hod_of_the_subjects_department_can_mark_a_topic_regardless_of_timetable_assignment(): void
    {
        [, , $hod, , , $section, $topic] = $this->makeFixtures();

        $this->actingAs($hod, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section))
            ->assertOk();
    }

    public function test_an_hod_outside_the_subjects_department_cannot_mark_a_topic(): void
    {
        [$school, , , , , $section, $topic] = $this->makeFixtures();
        $otherHod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        Department::factory()->forSchool($school)->withHod($otherHod)->create();

        $this->actingAs($otherHod, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section))
            ->assertForbidden();
    }

    public function test_a_school_admin_can_mark_a_topic(): void
    {
        [$school, , , , , $section, $topic] = $this->makeFixtures();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section))
            ->assertOk();
    }

    public function test_a_school_admin_from_another_school_cannot_mark_a_topic(): void
    {
        [, , , , , $section, $topic] = $this->makeFixtures();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherAdmin, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section))
            ->assertForbidden();
    }

    public function test_a_class_section_from_a_different_school_than_the_topic_is_rejected(): void
    {
        [, , , , $teacher, , $topic] = $this->makeFixtures();
        $sectionElsewhere = ClassSection::factory()->create();

        $this->actingAs($teacher, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $sectionElsewhere))
            ->assertUnprocessable();
    }

    public function test_a_super_admin_can_mark_a_topic(): void
    {
        [, , , , , $section, $topic] = $this->makeFixtures();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson('/api/v1/syllabus-progress', $this->togglePayload($topic, $section))
            ->assertOk();
    }

    public function test_a_nonexistent_syllabus_topic_id_is_rejected(): void
    {
        [, , , , $teacher, $section] = $this->makeFixtures();

        $this->actingAs($teacher, 'sanctum')->patchJson('/api/v1/syllabus-progress', [
            'syllabus_topic_id' => 999999,
            'class_section_id' => $section->id,
            'completed' => true,
        ])->assertUnprocessable();
    }

    public function test_completed_must_be_a_boolean(): void
    {
        [, , , , $teacher, $section, $topic] = $this->makeFixtures();

        $this->actingAs($teacher, 'sanctum')->patchJson('/api/v1/syllabus-progress', [
            'syllabus_topic_id' => $topic->id,
            'class_section_id' => $section->id,
            'completed' => 'yes-please',
        ])->assertUnprocessable();
    }

    // ── checklist (view) ─────────────────────────────────────────────────

    public function test_the_checklist_shows_every_topic_with_its_completion_status(): void
    {
        [, , , $subject, $teacher, $section, $topic] = $this->makeFixtures();
        $secondTopic = SyllabusTopic::factory()->forSubject($subject)->atSequence(2)->create();
        SyllabusTopicProgress::factory()->forTopic($topic)->forSection($section)->completedBy($teacher)->create();

        $response = $this->actingAs($teacher, 'sanctum')
            ->getJson("/api/v1/syllabus-progress?class_section_id={$section->id}&subject_id={$subject->id}");

        $response->assertOk()
            ->assertJsonPath('total_topics', 2)
            ->assertJsonPath('completed_topics', 1)
            ->assertJsonPath('progress_percent', 50)
            ->assertJsonPath('topics.0.id', $topic->id)
            ->assertJsonPath('topics.0.completed', true)
            ->assertJsonPath('topics.1.id', $secondTopic->id)
            ->assertJsonPath('topics.1.completed', false);
    }

    public function test_a_staff_member_cannot_view_the_checklist(): void
    {
        [$school, , , $subject, , $section] = $this->makeFixtures();
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();

        $this->actingAs($staff, 'sanctum')
            ->getJson("/api/v1/syllabus-progress?class_section_id={$section->id}&subject_id={$subject->id}")
            ->assertForbidden();
    }

    public function test_a_teacher_from_another_school_cannot_view_the_checklist(): void
    {
        [, , , $subject, , $section] = $this->makeFixtures();
        $outsider = User::factory()->role(UserRole::Teacher)->forSchool(School::factory()->create())->create();

        $this->actingAs($outsider, 'sanctum')
            ->getJson("/api/v1/syllabus-progress?class_section_id={$section->id}&subject_id={$subject->id}")
            ->assertForbidden();
    }

    public function test_a_super_admin_can_view_any_schools_checklist(): void
    {
        [, , , $subject, , $section] = $this->makeFixtures();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson("/api/v1/syllabus-progress?class_section_id={$section->id}&subject_id={$subject->id}")
            ->assertOk();
    }
}

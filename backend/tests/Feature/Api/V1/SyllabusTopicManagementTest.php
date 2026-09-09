<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\School;
use App\Models\Subject;
use App\Models\SyllabusTopic;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SyllabusTopicManagementTest extends TestCase
{
    use RefreshDatabase;

    /**
     * @return array{0: School, 1: Department, 2: User, 3: Subject}
     */
    private function makeSubjectWithHod(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->withHod($hod)->create();
        $subject = Subject::factory()->forDepartment($department)->create();

        return [$school, $department, $hod, $subject];
    }

    // ── create ───────────────────────────────────────────────────────────

    public function test_a_school_admin_can_create_a_topic_for_a_subject_in_their_own_school(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'subject_id' => $subject->id,
            'title' => 'Chapter 1: Whole Numbers',
            'sequence_number' => 1,
        ]);

        $response->assertCreated()
            ->assertJsonPath('subject_id', $subject->id)
            ->assertJsonPath('title', 'Chapter 1: Whole Numbers')
            ->assertJsonPath('sequence_number', 1);
        $this->assertDatabaseHas('syllabus_topics', ['school_id' => $school->id, 'subject_id' => $subject->id]);
    }

    public function test_a_school_admin_can_create_a_topic_even_when_the_client_sends_a_null_school_id(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'school_id' => null,
            'subject_id' => $subject->id,
            'title' => 'Chapter 1',
            'sequence_number' => 1,
        ])->assertCreated();
    }

    public function test_the_hod_of_the_subjects_department_can_create_a_topic(): void
    {
        [, , $hod, $subject] = $this->makeSubjectWithHod();

        $this->actingAs($hod, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'subject_id' => $subject->id,
            'title' => 'Chapter 1',
            'sequence_number' => 1,
        ])->assertCreated();
    }

    public function test_an_hod_outside_the_subjects_department_cannot_create_a_topic(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $otherHod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        Department::factory()->forSchool($school)->withHod($otherHod)->create();

        $this->actingAs($otherHod, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'subject_id' => $subject->id,
            'title' => 'Chapter 1',
            'sequence_number' => 1,
        ])->assertForbidden();
    }

    public function test_a_teacher_cannot_create_a_topic(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'subject_id' => $subject->id,
            'title' => 'Chapter 1',
            'sequence_number' => 1,
        ])->assertForbidden();
    }

    public function test_a_school_admin_cannot_create_a_topic_for_another_schools_subject(): void
    {
        [, , , $subjectElsewhere] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'subject_id' => $subjectElsewhere->id,
            'title' => 'Chapter 1',
            'sequence_number' => 1,
        ])->assertUnprocessable();
    }

    public function test_a_super_admin_can_create_a_topic_for_any_school(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'school_id' => $school->id,
            'subject_id' => $subject->id,
            'title' => 'Chapter 1',
            'sequence_number' => 1,
        ])->assertCreated();
    }

    public function test_duplicate_sequence_number_for_the_same_subject_is_rejected(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'subject_id' => $subject->id,
            'title' => 'Another Chapter 1',
            'sequence_number' => 1,
        ])->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['sequence_number']]]);
    }

    public function test_the_same_sequence_number_is_allowed_for_a_different_subject(): void
    {
        [$school, $department, , $subject] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();
        $otherSubject = Subject::factory()->forDepartment($department)->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'subject_id' => $otherSubject->id,
            'title' => 'Chapter 1',
            'sequence_number' => 1,
        ])->assertCreated();
    }

    public function test_a_title_exceeding_the_max_length_is_rejected(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')->postJson('/api/v1/syllabus-topics', [
            'subject_id' => $subject->id,
            'title' => str_repeat('a', 256),
            'sequence_number' => 1,
        ])->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['title']]]);
    }

    // ── update ───────────────────────────────────────────────────────────

    public function test_a_school_admin_can_rename_a_topic(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/syllabus-topics/{$topic->id}", ['title' => 'Renamed Chapter']);

        $response->assertOk()->assertJsonPath('title', 'Renamed Chapter');
    }

    public function test_the_hod_of_the_subjects_department_can_update_a_topic(): void
    {
        [, , $hod, $subject] = $this->makeSubjectWithHod();
        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();

        $this->actingAs($hod, 'sanctum')
            ->patchJson("/api/v1/syllabus-topics/{$topic->id}", ['title' => 'Renamed'])
            ->assertOk();
    }

    public function test_an_hod_outside_the_subjects_department_cannot_update_a_topic(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();
        $otherHod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();
        Department::factory()->forSchool($school)->withHod($otherHod)->create();

        $this->actingAs($otherHod, 'sanctum')
            ->patchJson("/api/v1/syllabus-topics/{$topic->id}", ['title' => 'Renamed'])
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_update_a_topic(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')
            ->patchJson("/api/v1/syllabus-topics/{$topic->id}", ['title' => 'Renamed'])
            ->assertForbidden();
    }

    public function test_a_school_admin_cannot_update_a_topic_from_another_school(): void
    {
        [, , , $subject] = $this->makeSubjectWithHod();
        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherAdmin, 'sanctum')
            ->patchJson("/api/v1/syllabus-topics/{$topic->id}", ['title' => 'Renamed'])
            ->assertForbidden();
    }

    public function test_updating_to_a_sequence_number_already_used_by_another_topic_is_rejected(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();
        $topic2 = SyllabusTopic::factory()->forSubject($subject)->atSequence(2)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/syllabus-topics/{$topic2->id}", ['sequence_number' => 1])
            ->assertUnprocessable();
    }

    // ── delete ───────────────────────────────────────────────────────────

    public function test_a_school_admin_can_delete_a_topic(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/syllabus-topics/{$topic->id}")->assertNoContent();
        $this->assertDatabaseMissing('syllabus_topics', ['id' => $topic->id]);
    }

    public function test_a_teacher_cannot_delete_a_topic(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->deleteJson("/api/v1/syllabus-topics/{$topic->id}")->assertForbidden();
    }

    public function test_a_school_admin_cannot_delete_a_topic_from_another_school(): void
    {
        [, , , $subject] = $this->makeSubjectWithHod();
        $topic = SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create();
        $otherAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();

        $this->actingAs($otherAdmin, 'sanctum')
            ->deleteJson("/api/v1/syllabus-topics/{$topic->id}")
            ->assertForbidden();
    }

    // ── list ─────────────────────────────────────────────────────────────

    public function test_a_teacher_can_list_topics_for_a_subject_ordered_by_sequence(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        SyllabusTopic::factory()->forSubject($subject)->atSequence(2)->create(['title' => 'Second']);
        SyllabusTopic::factory()->forSubject($subject)->atSequence(1)->create(['title' => 'First']);

        $response = $this->actingAs($teacher, 'sanctum')->getJson("/api/v1/syllabus-topics?subject_id={$subject->id}");

        // A non-paginated resource collection returns a bare JSON array
        // (AppServiceProvider calls JsonResource::withoutWrapping()) - no
        // top-level "data" key to unwrap, unlike paginated endpoints.
        $response->assertOk();
        $this->assertSame(['First', 'Second'], collect($response->json())->pluck('title')->all());
    }

    public function test_a_staff_member_cannot_list_syllabus_topics(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();

        $this->actingAs($staff, 'sanctum')
            ->getJson("/api/v1/syllabus-topics?subject_id={$subject->id}")
            ->assertForbidden();
    }

    public function test_a_transport_manager_cannot_list_syllabus_topics(): void
    {
        [$school, , , $subject] = $this->makeSubjectWithHod();
        $transportManager = User::factory()->role(UserRole::TransportManager)->forSchool($school)->create();

        $this->actingAs($transportManager, 'sanctum')
            ->getJson("/api/v1/syllabus-topics?subject_id={$subject->id}")
            ->assertForbidden();
    }
}

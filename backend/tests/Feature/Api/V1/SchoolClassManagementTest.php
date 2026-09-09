<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SchoolClassManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_school_admin_can_create_a_class_within_their_own_academic_year(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/classes', [
            'academic_year_id' => $year->id,
            'name' => 'Grade 8',
            'level' => 8,
        ]);

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('academic_year_id', $year->id)
            ->assertJsonPath('name', 'Grade 8');
    }

    public function test_a_school_admin_can_create_a_class_even_when_the_client_sends_a_null_school_id(): void
    {
        // The real Flutter client always sends the school_id key (as
        // literal null for a non-SuperAdmin, since it can't know the
        // actor's school) rather than omitting it - a bare `integer` rule
        // without `nullable` rejects that, even though `requiredIf` makes
        // the field optional for this actor. See StoreSchoolClassRequest.
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/classes', [
            'school_id' => null,
            'academic_year_id' => $year->id,
            'name' => 'Grade 9',
            'level' => 9,
        ]);

        $response->assertCreated()->assertJsonPath('school_id', $school->id);
    }

    public function test_an_academic_year_from_another_school_is_rejected(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $yearElsewhere = AcademicYear::factory()->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/classes', ['academic_year_id' => $yearElsewhere->id, 'name' => 'Grade 8', 'level' => 8])
            ->assertUnprocessable();
    }

    public function test_a_school_admin_can_add_a_section_with_a_class_teacher_to_their_own_class(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($year)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson("/api/v1/classes/{$schoolClass->id}/sections", [
            'name' => 'A',
            'room_number' => 'Room 204',
            'class_teacher_id' => $teacher->id,
        ]);

        $response->assertCreated()
            ->assertJsonPath('name', 'A')
            ->assertJsonPath('room_number', 'Room 204')
            ->assertJsonPath('class_teacher_id', $teacher->id);
    }

    public function test_a_school_admin_cannot_add_a_section_to_a_class_in_another_school(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $classElsewhere = SchoolClass::factory()
            ->forAcademicYear(AcademicYear::factory()->forSchool($otherSchool)->create())
            ->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/classes/{$classElsewhere->id}/sections", ['name' => 'A'])
            ->assertForbidden();
    }

    public function test_a_class_teacher_from_a_different_school_is_rejected(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();
        $teacherElsewhere = User::factory()->role(UserRole::Teacher)->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/classes/{$schoolClass->id}/sections", [
                'name' => 'A',
                'class_teacher_id' => $teacherElsewhere->id,
            ])
            ->assertUnprocessable();
    }

    public function test_section_names_are_unique_per_class(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();
        ClassSection::factory()->forClass($schoolClass)->create(['name' => 'A']);

        $this->actingAs($admin, 'sanctum')
            ->postJson("/api/v1/classes/{$schoolClass->id}/sections", ['name' => 'A'])
            ->assertUnprocessable();
    }

    public function test_deleting_a_class_that_still_has_sections_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();
        ClassSection::factory()->forClass($schoolClass)->create();

        $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/v1/classes/{$schoolClass->id}")
            ->assertStatus(409)
            ->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
    }

    public function test_a_school_admin_can_filter_classes_by_academic_year(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $yearA = AcademicYear::factory()->forSchool($school)->create();
        $yearB = AcademicYear::factory()->forSchool($school)->create();
        SchoolClass::factory()->forAcademicYear($yearA)->count(2)->create();
        SchoolClass::factory()->forAcademicYear($yearB)->count(3)->create();

        $response = $this->actingAs($admin, 'sanctum')->getJson("/api/v1/classes?academic_year_id={$yearA->id}");

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_a_school_admin_cannot_view_a_class_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $classB = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($schoolB)->create())->create();

        $this->actingAs($adminA, 'sanctum')
            ->getJson("/api/v1/classes/{$classB->id}")
            ->assertForbidden();
    }

    // ── update / delete a class ─────────────────────────────────────────

    public function test_a_school_admin_can_rename_a_class_in_their_own_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/classes/{$schoolClass->id}", ['name' => 'Grade 9']);

        $response->assertOk()->assertJsonPath('name', 'Grade 9');
    }

    public function test_a_school_admin_cannot_update_a_class_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $classB = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($schoolB)->create())->create();

        $this->actingAs($adminA, 'sanctum')
            ->patchJson("/api/v1/classes/{$classB->id}", ['name' => 'Grade 9'])
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_update_a_class(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();

        $this->actingAs($teacher, 'sanctum')
            ->patchJson("/api/v1/classes/{$schoolClass->id}", ['name' => 'Grade 9'])
            ->assertForbidden();
    }

    public function test_a_school_admin_can_delete_an_empty_class(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/classes/{$schoolClass->id}")->assertNoContent();
        $this->assertDatabaseMissing('school_classes', ['id' => $schoolClass->id]);
    }

    public function test_a_school_admin_cannot_delete_a_class_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $classB = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($schoolB)->create())->create();

        $this->actingAs($adminA, 'sanctum')->deleteJson("/api/v1/classes/{$classB->id}")->assertForbidden();
    }

    public function test_a_class_name_exceeding_the_max_length_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $year = AcademicYear::factory()->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/classes', [
            'academic_year_id' => $year->id,
            'name' => str_repeat('a', 51),
            'level' => 8,
        ]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['name']]]);
    }

    // ── update / delete a section ───────────────────────────────────────

    public function test_a_school_admin_can_rename_a_section_in_their_own_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();
        $section = ClassSection::factory()->forClass($schoolClass)->create(['name' => 'A']);

        $response = $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/sections/{$section->id}", ['name' => 'B']);

        $response->assertOk()->assertJsonPath('name', 'B');
    }

    public function test_a_school_admin_cannot_update_a_section_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $classB = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($schoolB)->create())->create();
        $sectionB = ClassSection::factory()->forClass($classB)->create();

        $this->actingAs($adminA, 'sanctum')
            ->patchJson("/api/v1/sections/{$sectionB->id}", ['name' => 'B'])
            ->assertForbidden();
    }

    public function test_updating_a_section_with_a_class_teacher_from_a_different_school_is_rejected(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();
        $section = ClassSection::factory()->forClass($schoolClass)->create();
        $teacherElsewhere = User::factory()->role(UserRole::Teacher)->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/sections/{$section->id}", ['class_teacher_id' => $teacherElsewhere->id])
            ->assertUnprocessable();
    }

    public function test_a_school_admin_can_delete_an_empty_section(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();
        $section = ClassSection::factory()->forClass($schoolClass)->create();

        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/sections/{$section->id}")->assertNoContent();
        $this->assertDatabaseMissing('class_sections', ['id' => $section->id]);
    }

    public function test_a_school_admin_cannot_delete_a_section_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $classB = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($schoolB)->create())->create();
        $sectionB = ClassSection::factory()->forClass($classB)->create();

        $this->actingAs($adminA, 'sanctum')->deleteJson("/api/v1/sections/{$sectionB->id}")->assertForbidden();
    }

    public function test_a_teacher_cannot_delete_a_section(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();
        $section = ClassSection::factory()->forClass($schoolClass)->create();

        $this->actingAs($teacher, 'sanctum')->deleteJson("/api/v1/sections/{$section->id}")->assertForbidden();
    }

    public function test_a_section_room_number_exceeding_the_max_length_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear(AcademicYear::factory()->forSchool($school)->create())->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson("/api/v1/classes/{$schoolClass->id}/sections", [
            'name' => 'A',
            'room_number' => str_repeat('a', 21),
        ]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['room_number']]]);
    }
}

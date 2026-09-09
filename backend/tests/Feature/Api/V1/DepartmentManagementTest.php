<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\School;
use App\Models\Subject;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DepartmentManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_school_admin_can_create_a_department_with_an_hod_from_their_own_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $hod = User::factory()->role(UserRole::Hod)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/departments', [
            'name' => 'Mathematics',
            'hod_user_id' => $hod->id,
        ]);

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('name', 'Mathematics')
            ->assertJsonPath('hod_user_id', $hod->id);
    }

    public function test_a_school_admin_can_create_a_department_even_when_the_client_sends_a_null_school_id(): void
    {
        // The real Flutter client always sends the school_id key (literal
        // null for a non-SuperAdmin) rather than omitting it - a bare
        // `integer` rule without `nullable` rejects that. See
        // StoreDepartmentRequest.
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/departments', [
            'school_id' => null,
            'name' => 'Science',
        ]);

        $response->assertCreated()->assertJsonPath('school_id', $school->id);
    }

    public function test_an_hod_from_a_different_school_is_rejected(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $hodElsewhere = User::factory()->role(UserRole::Hod)->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/departments', ['name' => 'Mathematics', 'hod_user_id' => $hodElsewhere->id])
            ->assertUnprocessable();
    }

    public function test_department_names_are_unique_per_school_but_not_globally(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        Department::factory()->forSchool($schoolA)->create(['name' => 'Science']);
        Department::factory()->forSchool($schoolB)->create(['name' => 'Science']);

        $this->actingAs($adminA, 'sanctum')
            ->postJson('/api/v1/departments', ['name' => 'Science'])
            ->assertUnprocessable();
    }

    public function test_a_school_admin_cannot_view_a_department_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $departmentB = Department::factory()->forSchool($schoolB)->create();

        $this->actingAs($adminA, 'sanctum')
            ->getJson("/api/v1/departments/{$departmentB->id}")
            ->assertForbidden();
    }

    public function test_deleting_a_department_that_still_has_subjects_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();
        Subject::factory()->forDepartment($department)->create();

        $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/v1/departments/{$department->id}")
            ->assertStatus(409)
            ->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
    }

    public function test_deleting_an_empty_department_succeeds(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->deleteJson("/api/v1/departments/{$department->id}")
            ->assertNoContent();

        $this->assertDatabaseMissing('departments', ['id' => $department->id]);
    }

    public function test_a_school_admin_can_rename_a_department_in_their_own_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create(['name' => 'Old Name']);

        $response = $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/departments/{$department->id}", ['name' => 'New Name']);

        $response->assertOk()->assertJsonPath('name', 'New Name');
    }

    public function test_a_school_admin_cannot_update_a_department_from_another_school(): void
    {
        $ownSchool = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($ownSchool)->create();
        $department = Department::factory()->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/departments/{$department->id}", ['name' => 'New Name'])
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_update_a_department(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')
            ->patchJson("/api/v1/departments/{$department->id}", ['name' => 'New Name'])
            ->assertForbidden();
    }

    public function test_updating_a_department_with_an_hod_from_a_different_school_is_rejected(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();
        $hodElsewhere = User::factory()->role(UserRole::Hod)->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/departments/{$department->id}", ['hod_user_id' => $hodElsewhere->id])
            ->assertUnprocessable();
    }

    public function test_a_department_name_exceeding_the_max_length_is_rejected(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/departments', ['name' => str_repeat('a', 101)]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['name']]]);
    }
}

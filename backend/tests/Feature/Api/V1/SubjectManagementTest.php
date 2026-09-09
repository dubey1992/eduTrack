<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\School;
use App\Models\Subject;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SubjectManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_school_admin_can_create_a_subject_under_their_own_department(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/subjects', [
            'department_id' => $department->id,
            'code' => 'MAT',
            'name' => 'Mathematics',
            'min_class_level' => 7,
            'max_class_level' => 10,
            'lead_teacher_id' => $teacher->id,
        ]);

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('department_id', $department->id)
            ->assertJsonPath('code', 'MAT')
            ->assertJsonPath('lead_teacher_id', $teacher->id);
    }

    public function test_a_school_admin_can_create_a_subject_even_when_the_client_sends_a_null_school_id(): void
    {
        // The real Flutter client always sends the school_id key (literal
        // null for a non-SuperAdmin) rather than omitting it - a bare
        // `integer` rule without `nullable` rejects that. See
        // StoreSubjectRequest.
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/subjects', [
            'school_id' => null,
            'department_id' => $department->id,
            'code' => 'SCI',
            'name' => 'Science',
            'min_class_level' => 6,
            'max_class_level' => 10,
        ]);

        $response->assertCreated()->assertJsonPath('school_id', $school->id);
    }

    public function test_a_department_from_another_school_is_rejected(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $departmentElsewhere = Department::factory()->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/subjects', [
                'department_id' => $departmentElsewhere->id,
                'code' => 'MAT',
                'name' => 'Mathematics',
                'min_class_level' => 1,
                'max_class_level' => 5,
            ])
            ->assertUnprocessable();
    }

    public function test_max_class_level_must_be_at_or_above_min_class_level(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/subjects', [
                'department_id' => $department->id,
                'code' => 'MAT',
                'name' => 'Mathematics',
                'min_class_level' => 8,
                'max_class_level' => 5,
            ])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['max_class_level']]]);
    }

    public function test_subject_codes_are_unique_per_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();
        Subject::factory()->forDepartment($department)->create(['code' => 'MAT']);

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/subjects', [
                'department_id' => $department->id,
                'code' => 'MAT',
                'name' => 'Mathematics II',
                'min_class_level' => 1,
                'max_class_level' => 5,
            ])
            ->assertUnprocessable();
    }

    public function test_a_school_admin_can_filter_subjects_by_department(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $mathDept = Department::factory()->forSchool($school)->create(['name' => 'Mathematics']);
        $scienceDept = Department::factory()->forSchool($school)->create(['name' => 'Science']);
        Subject::factory()->forDepartment($mathDept)->count(2)->create();
        Subject::factory()->forDepartment($scienceDept)->count(3)->create();

        $response = $this->actingAs($admin, 'sanctum')->getJson("/api/v1/subjects?department_id={$mathDept->id}");

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_a_school_admin_cannot_view_a_subject_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $subjectB = Subject::factory()->forDepartment(Department::factory()->forSchool($schoolB)->create())->create();

        $this->actingAs($adminA, 'sanctum')
            ->getJson("/api/v1/subjects/{$subjectB->id}")
            ->assertForbidden();
    }
}

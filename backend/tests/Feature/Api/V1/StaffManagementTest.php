<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\Department;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\StaffProfile;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class StaffManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_school_admin_can_add_an_employee_which_creates_the_account_and_profile_together(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/staff', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'mobile' => '+91 9876543210',
            'password' => 'password123',
            'role' => 'TEACHER',
            'employee_id' => 'TCH-012',
            'department_id' => $department->id,
            'designation' => 'Senior Teacher',
            'joining_date' => '2024-06-01',
            'address' => '12 MG Road',
        ]);

        $response->assertCreated()
            ->assertJsonPath('employee_id', 'TCH-012')
            ->assertJsonPath('email', 'priya.sharma@example.com')
            ->assertJsonPath('role', 'TEACHER')
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('department_name', $department->name);

        $this->assertDatabaseHas('users', ['email' => 'priya.sharma@example.com', 'school_id' => $school->id]);
        $this->assertDatabaseHas('staff_profiles', ['employee_id' => 'TCH-012', 'school_id' => $school->id]);
    }

    public function test_a_school_admin_can_add_an_employee_even_when_the_client_sends_a_null_school_id(): void
    {
        // The real Flutter client always sends the school_id key (literal
        // null for a non-SuperAdmin) rather than omitting it - a bare
        // `integer` rule without `nullable` rejects that. See
        // StoreStaffRequest.
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/staff', [
            'school_id' => null,
            'first_name' => 'Kavita',
            'last_name' => 'Nair',
            'email' => 'kavita.nair@example.com',
            'password' => 'password123',
            'role' => 'STAFF',
            'employee_id' => 'STF-006',
            'joining_date' => '2024-06-01',
        ]);

        $response->assertCreated()->assertJsonPath('school_id', $school->id);
    }

    public function test_a_school_admin_cannot_add_an_employee_with_an_admin_role(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/staff', [
                'first_name' => 'New',
                'last_name' => 'Admin',
                'email' => 'new.admin@example.com',
                'password' => 'password123',
                'role' => 'SCHOOL_ADMIN',
                'employee_id' => 'EMP-001',
                'joining_date' => '2026-01-01',
            ])
            ->assertUnprocessable();
    }

    public function test_a_super_admin_must_choose_a_school_for_a_new_employee(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/v1/staff', [
                'first_name' => 'New',
                'last_name' => 'Teacher',
                'email' => 'new.teacher@example.com',
                'password' => 'password123',
                'role' => 'TEACHER',
                'employee_id' => 'EMP-001',
                'joining_date' => '2026-01-01',
            ])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['school_id']]]);
    }

    public function test_employee_id_is_unique_per_school_but_not_globally(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        StaffProfile::factory()->forUser(User::factory()->role(UserRole::Teacher)->forSchool($schoolA)->create())
            ->create(['employee_id' => 'TCH-001']);
        StaffProfile::factory()->forUser(User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->create())
            ->create(['employee_id' => 'TCH-001']);

        $this->actingAs($adminA, 'sanctum')
            ->postJson('/api/v1/staff', [
                'first_name' => 'Another',
                'last_name' => 'Teacher',
                'email' => 'another.teacher@example.com',
                'password' => 'password123',
                'role' => 'TEACHER',
                'employee_id' => 'TCH-001',
                'joining_date' => '2026-01-01',
            ])
            ->assertUnprocessable();
    }

    public function test_a_department_from_another_school_is_rejected(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $departmentElsewhere = Department::factory()->forSchool($otherSchool)->create();

        $this->actingAs($admin, 'sanctum')
            ->postJson('/api/v1/staff', [
                'first_name' => 'New',
                'last_name' => 'Teacher',
                'email' => 'new.teacher@example.com',
                'password' => 'password123',
                'role' => 'TEACHER',
                'employee_id' => 'EMP-001',
                'department_id' => $departmentElsewhere->id,
                'joining_date' => '2026-01-01',
            ])
            ->assertUnprocessable();
    }

    public function test_a_school_admin_only_sees_staff_from_their_own_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        foreach (User::factory()->role(UserRole::Teacher)->forSchool($schoolA)->count(2)->create() as $teacher) {
            StaffProfile::factory()->forUser($teacher)->create();
        }
        foreach (User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->count(3)->create() as $teacher) {
            StaffProfile::factory()->forUser($teacher)->create();
        }

        $response = $this->actingAs($adminA, 'sanctum')->getJson('/api/v1/staff');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_a_school_admin_cannot_view_a_staff_profile_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $profileB = StaffProfile::factory()->forUser(User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->create())->create();

        $this->actingAs($adminA, 'sanctum')
            ->getJson("/api/v1/staff/{$profileB->id}")
            ->assertForbidden();
    }

    public function test_a_teacher_cannot_view_the_staff_directory(): void
    {
        $school = School::factory()->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')
            ->getJson('/api/v1/staff')
            ->assertForbidden();
    }

    public function test_a_school_admin_can_filter_staff_by_department(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $mathDept = Department::factory()->forSchool($school)->create();
        $scienceDept = Department::factory()->forSchool($school)->create();
        foreach (User::factory()->role(UserRole::Teacher)->forSchool($school)->count(2)->create() as $teacher) {
            StaffProfile::factory()->forUser($teacher)->forDepartment($mathDept)->create();
        }
        foreach (User::factory()->role(UserRole::Teacher)->forSchool($school)->count(3)->create() as $teacher) {
            StaffProfile::factory()->forUser($teacher)->forDepartment($scienceDept)->create();
        }

        $response = $this->actingAs($admin, 'sanctum')->getJson("/api/v1/staff?department_id={$mathDept->id}");

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_a_school_admin_can_update_a_staff_profiles_employment_details(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $department = Department::factory()->forSchool($school)->create();
        $profile = StaffProfile::factory()->forUser(User::factory()->role(UserRole::Teacher)->forSchool($school)->create())->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/staff/{$profile->id}", [
                'designation' => 'Head Teacher',
                'department_id' => $department->id,
            ])
            ->assertOk()
            ->assertJsonPath('designation', 'Head Teacher')
            ->assertJsonPath('department_id', $department->id);
    }

    public function test_assigned_classes_are_derived_from_class_teacher_assignments(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();
        $profile = StaffProfile::factory()->forUser($teacher)->create();
        $academicYear = AcademicYear::factory()->forSchool($school)->create();
        $schoolClass = SchoolClass::factory()->forAcademicYear($academicYear)->create(['name' => 'Grade 8']);
        ClassSection::factory()->forClass($schoolClass)->withClassTeacher($teacher)->create(['name' => 'A']);

        $response = $this->actingAs($admin, 'sanctum')->getJson("/api/v1/staff/{$profile->id}");

        $response->assertOk();
        $this->assertSame(['Grade 8 A'], $response->json('class_teacher_of'));
    }

    public function test_a_super_admin_is_not_restricted_by_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        StaffProfile::factory()->forUser(User::factory()->role(UserRole::Teacher)->forSchool($schoolA)->create())->create();
        StaffProfile::factory()->forUser(User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->create())->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/staff');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }
}

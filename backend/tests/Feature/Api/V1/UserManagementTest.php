<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class UserManagementTest extends TestCase
{
    use RefreshDatabase;

    public function test_super_admin_can_create_a_school_admin(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'mobile' => '+91 9876543210',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
            'school_id' => $school->id,
        ]);

        $response->assertCreated();
        $response->assertJsonPath('email', 'priya.sharma@example.com');
        $response->assertJsonPath('role', 'SCHOOL_ADMIN');
        $response->assertJsonPath('status', 'active');
        $this->assertDatabaseHas('users', ['email' => 'priya.sharma@example.com']);
    }

    /**
     * A School Admin otherwise has no StaffProfile at all, which would
     * block them from Staff Leave/Attendance self-service - a minimal
     * placeholder profile (no department, "ADMIN-{id}" employee id) is
     * created alongside the login so those work immediately.
     * See UserService::create().
     */
    public function test_creating_a_school_admin_also_creates_a_minimal_staff_profile(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
            'school_id' => $school->id,
        ]);

        $newAdminId = $response->json('id');
        $response->assertCreated();
        $this->assertDatabaseHas('staff_profiles', [
            'user_id' => $newAdminId,
            'school_id' => $school->id,
            'employee_id' => "ADMIN-{$newAdminId}",
            'department_id' => null,
        ]);
    }

    /**
     * This endpoint only ever creates School Admin accounts (see
     * UserPolicy::create()) - operational staff roles (HOD/Teacher/Staff/
     * Transport Manager) are onboarded via Teachers & Staff instead, which
     * creates its own, real StaffProfile as part of that flow.
     */
    public function test_super_admin_cannot_create_a_non_school_admin_role_via_this_endpoint(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'password' => 'password123',
            'role' => 'TEACHER',
            'school_id' => $school->id,
        ]);

        $response->assertUnprocessable();
        $this->assertDatabaseMissing('users', ['email' => 'priya.sharma@example.com']);
    }

    /**
     * A (non-sub) School Admin can create Sub Admins for their own school -
     * same SCHOOL_ADMIN role and permissions everywhere else, flagged
     * is_sub_admin so they can't create further admin accounts themselves.
     * See UserPolicy::create() and UserService::create().
     */
    public function test_a_school_admin_can_create_a_sub_admin(): void
    {
        $school = School::factory()->create();
        $schoolAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $response = $this->actingAs($schoolAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
        ]);

        $response->assertCreated()
            ->assertJsonPath('role', 'SCHOOL_ADMIN')
            ->assertJsonPath('is_sub_admin', true)
            ->assertJsonPath('school_id', $school->id);
        $this->assertDatabaseHas('users', [
            'email' => 'priya.sharma@example.com',
            'school_id' => $school->id,
            'is_sub_admin' => true,
        ]);
    }

    public function test_a_sub_admin_cannot_create_any_user(): void
    {
        $school = School::factory()->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);

        $response = $this->actingAs($subAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
        ]);

        $response->assertForbidden()->assertJsonPath('code', 'FORBIDDEN');
        $this->assertDatabaseMissing('users', ['email' => 'priya.sharma@example.com']);
    }

    public function test_a_non_super_admin_cannot_create_a_user(): void
    {
        $teacher = User::factory()->role(UserRole::Teacher)->create();

        $response = $this->actingAs($teacher, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'password' => 'password123',
            'role' => 'TEACHER',
        ]);

        $response->assertForbidden()->assertJsonPath('code', 'FORBIDDEN');
        $this->assertDatabaseMissing('users', ['email' => 'priya.sharma@example.com']);
    }

    public function test_an_unauthenticated_request_cannot_list_users(): void
    {
        $this->getJson('/api/v1/users')->assertUnauthorized();
    }

    public function test_creating_a_user_validates_required_fields_and_role(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'role' => 'PRINCIPAL',
        ]);

        $response->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['first_name', 'last_name', 'email', 'password', 'role']]]);
    }

    public function test_a_mobile_number_without_a_country_code_is_rejected(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'mobile' => '9876543210',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
            'school_id' => $school->id,
        ]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['mobile']]]);
    }

    public function test_a_nonexistent_school_id_is_rejected(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
            'school_id' => 999999,
        ]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['school_id']]]);
    }

    public function test_first_name_exceeding_the_max_length_is_rejected(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => str_repeat('a', 101),
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
            'school_id' => $school->id,
        ]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['first_name']]]);
    }

    public function test_a_super_admin_can_view_a_single_user(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->getJson("/api/v1/users/{$teacher->id}")
            ->assertOk()
            ->assertJsonPath('id', $teacher->id);
    }

    public function test_super_admin_can_list_and_filter_users(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        User::factory()->role(UserRole::Teacher)->count(2)->create();
        User::factory()->role(UserRole::Staff)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/users?role=TEACHER');

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_super_admin_can_filter_users_by_a_comma_separated_list_of_roles(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        User::factory()->role(UserRole::Hod)->create();
        User::factory()->role(UserRole::Teacher)->count(2)->create();
        User::factory()->role(UserRole::Staff)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/users?roles=HOD,TEACHER');

        $response->assertOk();
        $this->assertCount(3, $response->json('data'));
    }

    public function test_super_admin_can_filter_users_by_school(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        User::factory()->role(UserRole::Teacher)->forSchool($schoolA)->count(2)->create();
        User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson("/api/v1/users?school_id={$schoolA->id}");

        $response->assertOk();
        $this->assertCount(2, $response->json('data'));
    }

    public function test_super_admin_can_update_a_users_role(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $user = User::factory()->role(UserRole::Teacher)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/users/{$user->id}", ['role' => 'HOD']);

        $response->assertOk()->assertJsonPath('role', 'HOD');
    }

    public function test_super_admin_can_deactivate_and_reactivate_a_user(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $user = User::factory()->role(UserRole::Teacher)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/users/{$user->id}/deactivate")
            ->assertOk()
            ->assertJsonPath('status', 'inactive');

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/users/{$user->id}/activate")
            ->assertOk()
            ->assertJsonPath('status', 'active');
    }

    public function test_deactivating_a_user_revokes_their_existing_tokens(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $user = User::factory()->role(UserRole::Teacher)->create();
        $token = $user->createToken('api-token')->plainTextToken;

        $this->actingAs($superAdmin, 'sanctum')->patchJson("/api/v1/users/{$user->id}/deactivate")->assertOk();

        // See CLAUDE.md-adjacent note in AuthTest: the auth guard caches its
        // resolved user for the lifetime of a test, so force it to
        // re-resolve before the next request switches to a different user.
        $this->app['auth']->forgetGuards();

        $this->withHeader('Authorization', "Bearer {$token}")
            ->getJson('/api/v1/me')
            ->assertUnauthorized();
    }

    public function test_a_super_admin_cannot_deactivate_their_own_account(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/users/{$superAdmin->id}/deactivate")
            ->assertForbidden()
            ->assertJsonPath('code', 'FORBIDDEN');
    }
}

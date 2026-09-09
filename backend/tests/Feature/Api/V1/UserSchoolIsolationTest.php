<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/**
 * Locks in CLAUDE.md rule 12 (multi-school isolation) for the user
 * management endpoints introduced in Phase 1 and now scoped in Phase 2.
 */
class UserSchoolIsolationTest extends TestCase
{
    use RefreshDatabase;

    public function test_a_school_admin_only_sees_users_from_their_own_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        User::factory()->role(UserRole::Teacher)->forSchool($schoolA)->count(2)->create();
        User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->count(3)->create();

        $response = $this->actingAs($adminA, 'sanctum')->getJson('/api/v1/users');

        $response->assertOk();
        // Admin A themself + the 2 teachers in school A only.
        $this->assertCount(3, $response->json('data'));
    }

    public function test_a_school_admin_cannot_view_a_user_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $teacherB = User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->create();

        $this->actingAs($adminA, 'sanctum')
            ->getJson("/api/v1/users/{$teacherB->id}")
            ->assertForbidden();
    }

    public function test_a_school_admin_cannot_deactivate_a_user_from_another_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $adminA = User::factory()->role(UserRole::SchoolAdmin)->forSchool($schoolA)->create();
        $teacherB = User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->create();

        $this->actingAs($adminA, 'sanctum')
            ->patchJson("/api/v1/users/{$teacherB->id}/deactivate")
            ->assertForbidden();
    }

    public function test_a_school_admin_can_manage_a_user_within_their_own_school(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/users/{$teacher->id}/deactivate")
            ->assertOk()
            ->assertJsonPath('status', 'inactive');
    }

    /**
     * A School Admin's Sub Admin always lands in the actor's own school -
     * a client-supplied school_id is ignored server-side, never trusted.
     * See UserService::create().
     */
    public function test_a_sub_admin_created_by_a_school_admin_is_forced_into_the_admins_own_school(): void
    {
        $ownSchool = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($ownSchool)->create();

        $response = $this->actingAs($admin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Another',
            'last_name' => 'Admin',
            'email' => 'another.admin@example.com',
            'password' => 'password123',
            'role' => 'SCHOOL_ADMIN',
            'school_id' => $otherSchool->id,
        ]);

        $response->assertCreated()->assertJsonPath('school_id', $ownSchool->id);
    }

    /**
     * A Sub Admin has the same permissions as a School Admin everywhere
     * else, but can never create another admin account itself - only a
     * SUPER_ADMIN or the non-sub School Admin(s) who created it can.
     * See UserPolicy::create().
     */
    public function test_a_sub_admin_cannot_create_another_sub_admin(): void
    {
        $school = School::factory()->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);

        $this->actingAs($subAdmin, 'sanctum')
            ->postJson('/api/v1/users', [
                'first_name' => 'Another',
                'last_name' => 'Admin',
                'email' => 'another.admin@example.com',
                'password' => 'password123',
                'role' => 'SCHOOL_ADMIN',
            ])
            ->assertForbidden();
    }

    /**
     * The head (a School Admin who isn't themselves a Sub Admin) manages
     * the Sub Admins in their own school - editing and deactivating them,
     * same as any other account they're responsible for. See
     * UserPolicy::manages().
     */
    public function test_a_school_admin_can_deactivate_a_sub_admin_they_created(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/users/{$subAdmin->id}/deactivate")
            ->assertOk()
            ->assertJsonPath('status', 'inactive');
    }

    public function test_a_school_admin_can_update_a_sub_admin_they_created(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/users/{$subAdmin->id}", ['first_name' => 'Renamed'])
            ->assertOk()
            ->assertJsonPath('first_name', 'Renamed');
    }

    public function test_a_school_admin_cannot_deactivate_a_sub_admin_from_another_school(): void
    {
        $school = School::factory()->create();
        $otherSchool = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $subAdminElsewhere = User::factory()->role(UserRole::SchoolAdmin)->forSchool($otherSchool)
            ->create(['is_sub_admin' => true]);

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/users/{$subAdminElsewhere->id}/deactivate")
            ->assertForbidden();
    }

    public function test_a_super_admin_can_deactivate_a_sub_admin(): void
    {
        $school = School::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/users/{$subAdmin->id}/deactivate")
            ->assertOk()
            ->assertJsonPath('status', 'inactive');
    }

    public function test_a_school_admin_cannot_deactivate_a_peer_school_admin(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $peerAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/users/{$peerAdmin->id}/deactivate")
            ->assertForbidden();
    }

    public function test_a_sub_admin_cannot_deactivate_any_admin_account(): void
    {
        $school = School::factory()->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);
        $otherSubAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);

        $this->actingAs($subAdmin, 'sanctum')
            ->patchJson("/api/v1/users/{$otherSubAdmin->id}/deactivate")
            ->assertForbidden();
    }

    public function test_a_sub_admin_cannot_update_any_admin_account(): void
    {
        $school = School::factory()->create();
        $subAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);
        $otherSubAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(['is_sub_admin' => true]);

        $this->actingAs($subAdmin, 'sanctum')
            ->patchJson("/api/v1/users/{$otherSubAdmin->id}", ['first_name' => 'Renamed'])
            ->assertForbidden();
    }

    public function test_a_school_admin_cannot_promote_a_user_to_school_admin(): void
    {
        $school = School::factory()->create();
        $admin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($admin, 'sanctum')
            ->patchJson("/api/v1/users/{$teacher->id}", ['role' => 'SCHOOL_ADMIN'])
            ->assertUnprocessable();
    }

    public function test_a_super_admin_is_not_restricted_by_school(): void
    {
        $schoolA = School::factory()->create();
        $schoolB = School::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        User::factory()->role(UserRole::Teacher)->forSchool($schoolA)->create();
        User::factory()->role(UserRole::Teacher)->forSchool($schoolB)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/users');

        $response->assertOk();
        $this->assertCount(3, $response->json('data'));
    }
}

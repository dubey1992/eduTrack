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

    public function test_super_admin_can_create_a_user(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/users', [
            'first_name' => 'Priya',
            'last_name' => 'Sharma',
            'email' => 'priya.sharma@example.com',
            'mobile' => '+91 9876543210',
            'password' => 'password123',
            'role' => 'TEACHER',
            'school_id' => $school->id,
        ]);

        $response->assertCreated();
        $response->assertJsonPath('email', 'priya.sharma@example.com');
        $response->assertJsonPath('role', 'TEACHER');
        $response->assertJsonPath('status', 'active');
        $this->assertDatabaseHas('users', ['email' => 'priya.sharma@example.com']);
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
            'role' => 'TEACHER',
            'school_id' => $school->id,
        ]);

        $response->assertUnprocessable()->assertJsonStructure(['details' => ['errors' => ['mobile']]]);
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

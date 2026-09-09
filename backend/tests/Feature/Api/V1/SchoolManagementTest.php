<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class SchoolManagementTest extends TestCase
{
    use RefreshDatabase;

    private function validPayload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Sunrise Public School',
            'email' => 'admin@sunriseschool.edu',
            'phone' => '+91 98765 43210',
            'address' => '12 School Road',
            'city' => 'New Delhi',
            'state' => 'Delhi',
            'country' => 'India',
            'postal_code' => '110001',
            'currency_code' => 'INR',
        ], $overrides);
    }

    public function test_super_admin_can_create_a_school(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->postJson('/api/v1/schools', $this->validPayload());

        $response->assertCreated()
            ->assertJsonPath('name', 'Sunrise Public School')
            ->assertJsonPath('currency_code', 'INR')
            ->assertJsonPath('status', 'active');
    }

    public function test_a_non_super_admin_cannot_create_a_school(): void
    {
        $schoolAdmin = User::factory()->role(UserRole::SchoolAdmin)->create();

        $this->actingAs($schoolAdmin, 'sanctum')
            ->postJson('/api/v1/schools', $this->validPayload())
            ->assertForbidden();
    }

    public function test_currency_code_must_be_a_three_letter_format(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/v1/schools', $this->validPayload(['currency_code' => 'Rupees']))
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['currency_code']]]);
    }

    public function test_phone_must_include_a_country_code(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/v1/schools', $this->validPayload(['phone' => '9876543210']))
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['phone']]]);
    }

    public function test_super_admin_can_list_schools(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        School::factory()->count(3)->create();

        $response = $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/schools');

        $response->assertOk();
        $this->assertCount(3, $response->json('data'));
    }

    public function test_super_admin_can_deactivate_and_reactivate_a_school(): void
    {
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create();
        $school = School::factory()->create();

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/schools/{$school->id}/deactivate")
            ->assertOk()
            ->assertJsonPath('status', 'inactive');

        $this->actingAs($superAdmin, 'sanctum')
            ->patchJson("/api/v1/schools/{$school->id}/activate")
            ->assertOk()
            ->assertJsonPath('status', 'active');
    }

    public function test_a_school_admin_can_view_their_own_school(): void
    {
        $school = School::factory()->create();
        $schoolAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();

        $this->actingAs($schoolAdmin, 'sanctum')
            ->getJson("/api/v1/schools/{$school->id}")
            ->assertOk();
    }

    public function test_a_school_admin_cannot_view_another_school(): void
    {
        $ownSchool = School::factory()->create();
        $otherSchool = School::factory()->create();
        $schoolAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool($ownSchool)->create();

        $this->actingAs($schoolAdmin, 'sanctum')
            ->getJson("/api/v1/schools/{$otherSchool->id}")
            ->assertForbidden();
    }
}

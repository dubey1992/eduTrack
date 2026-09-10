<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\Driver;
use App\Models\School;
use App\Models\TransportRoute;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class DriverManagementTest extends TestCase
{
    use RefreshDatabase;

    private function payload(array $overrides = []): array
    {
        return array_merge([
            'name' => 'Sanjay Patel',
            'mobile' => '+91 9876543210',
            'licence_number' => 'MH-12-20190012345',
            'licence_expiry' => '2029-03-31',
        ], $overrides);
    }

    private function admin(School $school): User
    {
        return User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
    }

    public function test_a_school_admin_can_add_a_driver(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/drivers', $this->payload())
            ->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('name', 'Sanjay Patel')
            ->assertJsonPath('mobile', '+91 9876543210')
            ->assertJsonPath('licence_number', 'MH-12-20190012345')
            ->assertJsonPath('licence_expiry', '2029-03-31')
            ->assertJsonPath('status', 'active');
    }

    public function test_mobile_and_licence_expiry_are_optional_but_validated_when_given(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/drivers', $this->payload(['mobile' => null, 'licence_expiry' => null]))
            ->assertCreated()
            ->assertJsonPath('mobile', null)
            ->assertJsonPath('licence_expiry', null);
        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/drivers', $this->payload(['mobile' => '9876543210', 'licence_expiry' => 'soon', 'licence_number' => 'X-1']))
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['mobile', 'licence_expiry']]]);
    }

    public function test_name_and_licence_number_are_required(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/drivers', ['name' => '', 'licence_number' => ''])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['name', 'licence_number']]]);
    }

    public function test_the_licence_number_is_unique_per_school_only(): void
    {
        $school = School::factory()->create();
        Driver::factory()->forSchool($school)->create(['licence_number' => 'MH-12-20190012345']);
        Driver::factory()->create(['licence_number' => 'KA-01-1']);

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/drivers', $this->payload())
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['licence_number']]]);
        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/drivers', $this->payload(['licence_number' => 'KA-01-1']))
            ->assertCreated();
    }

    public function test_non_admin_roles_cannot_add_update_or_delete_drivers(): void
    {
        $school = School::factory()->create();
        $driver = Driver::factory()->forSchool($school)->create();

        foreach ([UserRole::Hod, UserRole::Teacher, UserRole::Staff, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->postJson('/api/v1/transport/drivers', $this->payload())->assertForbidden();
            $this->actingAs($user, 'sanctum')->patchJson("/api/v1/transport/drivers/{$driver->id}", ['name' => 'X'])->assertForbidden();
            $this->actingAs($user, 'sanctum')->deleteJson("/api/v1/transport/drivers/{$driver->id}")->assertForbidden();
        }
    }

    public function test_viewing_roles_see_their_schools_drivers_and_staff_sees_none(): void
    {
        $school = School::factory()->create();
        Driver::factory()->forSchool($school)->create(['name' => 'Sanjay Patel']);
        Driver::factory()->create(['name' => 'Elsewhere']);

        foreach ([UserRole::SchoolAdmin, UserRole::Hod, UserRole::Teacher, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->getJson('/api/v1/transport/drivers')
                ->assertOk()
                ->assertJsonCount(1, 'data')
                ->assertJsonPath('data.0.name', 'Sanjay Patel');
        }
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();
        $this->actingAs($staff, 'sanctum')->getJson('/api/v1/transport/drivers')->assertForbidden();
    }

    public function test_a_driver_from_another_school_cannot_be_viewed_updated_or_deleted(): void
    {
        $school = School::factory()->create();
        $foreign = Driver::factory()->create();
        $admin = $this->admin($school);

        $this->actingAs($admin, 'sanctum')->getJson("/api/v1/transport/drivers/{$foreign->id}")->assertForbidden();
        $this->actingAs($admin, 'sanctum')->patchJson("/api/v1/transport/drivers/{$foreign->id}", ['name' => 'X'])->assertForbidden();
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/transport/drivers/{$foreign->id}")->assertForbidden();
    }

    public function test_a_school_admin_can_update_and_deactivate_a_driver(): void
    {
        $school = School::factory()->create();
        $driver = Driver::factory()->forSchool($school)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/drivers/{$driver->id}", ['name' => 'Sanjay P.', 'status' => 'inactive'])
            ->assertOk()
            ->assertJsonPath('name', 'Sanjay P.')
            ->assertJsonPath('status', 'inactive');
    }

    public function test_a_driver_on_a_route_cannot_be_deleted_but_an_unused_one_can(): void
    {
        $school = School::factory()->create();
        $busy = Driver::factory()->forSchool($school)->create();
        $idle = Driver::factory()->forSchool($school)->create();
        $route = TransportRoute::factory()->forSchool($school)->withDriver($busy)->create(['name' => 'Lake Road']);

        $this->actingAs($this->admin($school), 'sanctum')
            ->getJson("/api/v1/transport/drivers/{$busy->id}")
            ->assertOk()
            ->assertJsonPath('route_id', $route->id)
            ->assertJsonPath('route_name', 'Lake Road');
        $this->actingAs($this->admin($school), 'sanctum')
            ->deleteJson("/api/v1/transport/drivers/{$busy->id}")
            ->assertConflict()
            ->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
        $this->actingAs($this->admin($school), 'sanctum')->deleteJson("/api/v1/transport/drivers/{$idle->id}")->assertNoContent();
        $this->assertDatabaseMissing('drivers', ['id' => $idle->id]);
    }
}

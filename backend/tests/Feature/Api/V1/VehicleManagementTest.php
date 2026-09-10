<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\TransportRoute;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class VehicleManagementTest extends TestCase
{
    use RefreshDatabase;

    private function payload(array $overrides = []): array
    {
        return array_merge(['name' => 'Bus 04', 'registration_number' => 'MH12 AB 1234', 'capacity' => 40], $overrides);
    }

    private function admin(School $school): User
    {
        return User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
    }

    // ── create ──────────────────────────────────────────────────────────

    public function test_a_school_admin_can_add_a_vehicle(): void
    {
        $school = School::factory()->create();

        $response = $this->actingAs($this->admin($school), 'sanctum')->postJson('/api/v1/transport/vehicles', $this->payload());

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('name', 'Bus 04')
            ->assertJsonPath('registration_number', 'MH12 AB 1234')
            ->assertJsonPath('capacity', 40)
            ->assertJsonPath('status', 'active')
            ->assertJsonPath('route_id', null);
    }

    public function test_a_school_admin_cannot_add_a_vehicle_to_another_school(): void
    {
        $school = School::factory()->create();
        $other = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/vehicles', $this->payload(['school_id' => $other->id]))
            ->assertCreated()
            ->assertJsonPath('school_id', $school->id);
    }

    public function test_a_super_admin_adds_a_vehicle_to_an_explicit_school(): void
    {
        $school = School::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/v1/transport/vehicles', $this->payload(['school_id' => $school->id]))
            ->assertCreated()
            ->assertJsonPath('school_id', $school->id);
        $this->actingAs($superAdmin, 'sanctum')
            ->postJson('/api/v1/transport/vehicles', $this->payload(['registration_number' => 'X 1']))
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['school_id']]]);
    }

    public function test_non_admin_roles_cannot_add_vehicles(): void
    {
        $school = School::factory()->create();

        foreach ([UserRole::Hod, UserRole::Teacher, UserRole::Staff, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->postJson('/api/v1/transport/vehicles', $this->payload())->assertForbidden();
        }
    }

    // ── validation ──────────────────────────────────────────────────────

    public function test_required_fields_and_capacity_bounds_are_validated(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/vehicles', ['name' => '', 'registration_number' => '', 'capacity' => 0])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['name', 'registration_number', 'capacity']]]);
        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/vehicles', $this->payload(['capacity' => 201]))
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['capacity']]]);
    }

    public function test_the_registration_number_is_unique_per_school_only(): void
    {
        $school = School::factory()->create();
        Vehicle::factory()->forSchool($school)->create(['registration_number' => 'MH12 AB 1234']);
        Vehicle::factory()->create(['registration_number' => 'KA01 ZZ 9999']);

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/vehicles', $this->payload())
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['registration_number']]]);
        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/vehicles', $this->payload(['registration_number' => 'KA01 ZZ 9999']))
            ->assertCreated();
    }

    // ── list / show ─────────────────────────────────────────────────────

    public function test_viewing_roles_see_only_their_schools_vehicles_and_staff_sees_none(): void
    {
        $school = School::factory()->create();
        Vehicle::factory()->forSchool($school)->create(['name' => 'Bus 01']);
        Vehicle::factory()->create(['name' => 'Elsewhere']);

        foreach ([UserRole::SchoolAdmin, UserRole::Hod, UserRole::Teacher, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->getJson('/api/v1/transport/vehicles')
                ->assertOk()
                ->assertJsonCount(1, 'data')
                ->assertJsonPath('data.0.name', 'Bus 01');
        }

        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();
        $this->actingAs($staff, 'sanctum')->getJson('/api/v1/transport/vehicles')->assertForbidden();
    }

    public function test_a_super_admin_can_filter_the_list_by_school_and_status(): void
    {
        $school = School::factory()->create();
        Vehicle::factory()->forSchool($school)->create();
        Vehicle::factory()->forSchool($school)->inactive()->create();
        Vehicle::factory()->create();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')->getJson('/api/v1/transport/vehicles')->assertOk()->assertJsonCount(3, 'data');
        $this->actingAs($superAdmin, 'sanctum')
            ->getJson("/api/v1/transport/vehicles?school_id={$school->id}&status=active")
            ->assertOk()
            ->assertJsonCount(1, 'data');
    }

    public function test_the_list_shows_which_route_a_vehicle_serves(): void
    {
        $school = School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->create();
        $route = TransportRoute::factory()->forSchool($school)->withVehicle($vehicle)->create(['name' => 'Green Park']);

        $this->actingAs($this->admin($school), 'sanctum')
            ->getJson('/api/v1/transport/vehicles')
            ->assertOk()
            ->assertJsonPath('data.0.route_id', $route->id)
            ->assertJsonPath('data.0.route_name', 'Green Park');
    }

    public function test_a_vehicle_from_another_school_cannot_be_viewed_updated_or_deleted(): void
    {
        $school = School::factory()->create();
        $foreign = Vehicle::factory()->create();
        $admin = $this->admin($school);

        $this->actingAs($admin, 'sanctum')->getJson("/api/v1/transport/vehicles/{$foreign->id}")->assertForbidden();
        $this->actingAs($admin, 'sanctum')->patchJson("/api/v1/transport/vehicles/{$foreign->id}", ['name' => 'X'])->assertForbidden();
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/transport/vehicles/{$foreign->id}")->assertForbidden();
    }

    // ── update / delete ─────────────────────────────────────────────────

    public function test_a_school_admin_can_update_and_deactivate_a_vehicle(): void
    {
        $school = School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/vehicles/{$vehicle->id}", ['capacity' => 52, 'status' => 'inactive'])
            ->assertOk()
            ->assertJsonPath('capacity', 52)
            ->assertJsonPath('status', 'inactive');
        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/vehicles/{$vehicle->id}", ['status' => 'scrapped'])
            ->assertUnprocessable();
    }

    public function test_a_teacher_cannot_update_or_delete_a_vehicle(): void
    {
        $school = School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->create();
        $teacher = User::factory()->role(UserRole::Teacher)->forSchool($school)->create();

        $this->actingAs($teacher, 'sanctum')->patchJson("/api/v1/transport/vehicles/{$vehicle->id}", ['name' => 'X'])->assertForbidden();
        $this->actingAs($teacher, 'sanctum')->deleteJson("/api/v1/transport/vehicles/{$vehicle->id}")->assertForbidden();
    }

    public function test_a_vehicle_serving_a_route_cannot_be_deleted(): void
    {
        $school = School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->create();
        TransportRoute::factory()->forSchool($school)->withVehicle($vehicle)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->deleteJson("/api/v1/transport/vehicles/{$vehicle->id}")
            ->assertConflict()
            ->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
        $this->assertDatabaseHas('vehicles', ['id' => $vehicle->id]);
    }

    public function test_an_unused_vehicle_can_be_deleted(): void
    {
        $school = School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->create();

        $this->actingAs($this->admin($school), 'sanctum')->deleteJson("/api/v1/transport/vehicles/{$vehicle->id}")->assertNoContent();
        $this->assertDatabaseMissing('vehicles', ['id' => $vehicle->id]);
    }
}

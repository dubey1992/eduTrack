<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\Driver;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\Student;
use App\Models\StudentTransportAssignment;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

class TransportRouteManagementTest extends TestCase
{
    use RefreshDatabase;

    private function admin(School $school): User
    {
        return User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create();
    }

    private function makeStudent(School $school): Student
    {
        $year = AcademicYear::factory()->forSchool($school)->create();
        $section = ClassSection::factory()->forClass(SchoolClass::factory()->forAcademicYear($year)->create())->create();

        return Student::factory()->forSection($section)->create();
    }

    // ── routes: create ──────────────────────────────────────────────────

    public function test_a_school_admin_can_create_a_route_with_a_vehicle_and_driver(): void
    {
        $school = School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->capacity(30)->create(['name' => 'Bus 04']);
        $driver = Driver::factory()->forSchool($school)->create(['name' => 'Sanjay Patel']);

        $response = $this->actingAs($this->admin($school), 'sanctum')->postJson('/api/v1/transport/routes', [
            'name' => 'Green Park',
            'vehicle_id' => $vehicle->id,
            'driver_id' => $driver->id,
        ]);

        $response->assertCreated()
            ->assertJsonPath('school_id', $school->id)
            ->assertJsonPath('name', 'Green Park')
            ->assertJsonPath('label', 'Bus 04 - Green Park')
            ->assertJsonPath('vehicle_name', 'Bus 04')
            ->assertJsonPath('capacity', 30)
            ->assertJsonPath('driver_name', 'Sanjay Patel')
            ->assertJsonPath('stops_count', 0)
            ->assertJsonPath('students_count', 0)
            ->assertJsonPath('stops', []);
    }

    public function test_a_route_without_a_vehicle_uses_its_plain_name_as_label(): void
    {
        $school = School::factory()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/routes', ['name' => 'Lake Road', 'vehicle_id' => null, 'driver_id' => null])
            ->assertCreated()
            ->assertJsonPath('label', 'Lake Road')
            ->assertJsonPath('capacity', null);
    }

    public function test_a_route_name_is_unique_per_school(): void
    {
        $school = School::factory()->create();
        TransportRoute::factory()->forSchool($school)->create(['name' => 'Green Park']);
        TransportRoute::factory()->create(['name' => 'Green Park']);

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/routes', ['name' => 'Green Park'])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['name']]]);
    }

    public function test_a_vehicle_or_driver_from_another_school_or_inactive_is_rejected(): void
    {
        $school = School::factory()->create();
        $foreignVehicle = Vehicle::factory()->create();
        $inactiveDriver = Driver::factory()->forSchool($school)->inactive()->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/routes', ['name' => 'X', 'vehicle_id' => $foreignVehicle->id, 'driver_id' => $inactiveDriver->id])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['vehicle_id', 'driver_id']]]);
    }

    public function test_a_vehicle_or_driver_already_on_another_route_is_rejected(): void
    {
        $school = School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->create();
        $driver = Driver::factory()->forSchool($school)->create();
        TransportRoute::factory()->forSchool($school)->withVehicle($vehicle)->withDriver($driver)->create();

        $response = $this->actingAs($this->admin($school), 'sanctum')
            ->postJson('/api/v1/transport/routes', ['name' => 'Second', 'vehicle_id' => $vehicle->id, 'driver_id' => $driver->id]);

        $response->assertUnprocessable()
            ->assertJsonPath('details.errors.vehicle_id.0', 'That vehicle is already serving another route.')
            ->assertJsonPath('details.errors.driver_id.0', 'That driver is already assigned to another route.');
    }

    public function test_non_admin_roles_cannot_create_routes(): void
    {
        $school = School::factory()->create();

        foreach ([UserRole::Hod, UserRole::Teacher, UserRole::Staff, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->postJson('/api/v1/transport/routes', ['name' => 'X'])->assertForbidden();
        }
    }

    // ── routes: update / delete ─────────────────────────────────────────

    public function test_updating_a_route_keeps_its_own_vehicle_valid_and_can_swap_it(): void
    {
        $school = School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->create();
        $other = Vehicle::factory()->forSchool($school)->create(['name' => 'Bus 09']);
        $route = TransportRoute::factory()->forSchool($school)->withVehicle($vehicle)->create();

        // Same vehicle again (the unique rule must ignore this route itself).
        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/routes/{$route->id}", ['name' => 'Renamed', 'vehicle_id' => $vehicle->id])
            ->assertOk()
            ->assertJsonPath('name', 'Renamed');
        // A now-inactive current vehicle is still allowed to stay, but a new inactive one is not.
        $vehicle->update(['status' => 'inactive']);
        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/routes/{$route->id}", ['vehicle_id' => $vehicle->id])
            ->assertOk();
        $other->update(['status' => 'inactive']);
        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/routes/{$route->id}", ['vehicle_id' => $other->id])
            ->assertUnprocessable();
        $other->update(['status' => 'active']);
        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/routes/{$route->id}", ['vehicle_id' => $other->id, 'status' => 'inactive'])
            ->assertOk()
            ->assertJsonPath('vehicle_name', 'Bus 09')
            ->assertJsonPath('status', 'inactive');
    }

    public function test_a_route_can_drop_its_vehicle_and_driver(): void
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)
            ->withVehicle(Vehicle::factory()->forSchool($school)->create())
            ->withDriver(Driver::factory()->forSchool($school)->create())
            ->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/routes/{$route->id}", ['vehicle_id' => null, 'driver_id' => null])
            ->assertOk()
            ->assertJsonPath('vehicle_id', null)
            ->assertJsonPath('driver_id', null);
    }

    public function test_a_route_from_another_school_cannot_be_touched(): void
    {
        $school = School::factory()->create();
        $foreign = TransportRoute::factory()->create();
        $admin = $this->admin($school);

        $this->actingAs($admin, 'sanctum')->getJson("/api/v1/transport/routes/{$foreign->id}")->assertForbidden();
        $this->actingAs($admin, 'sanctum')->patchJson("/api/v1/transport/routes/{$foreign->id}", ['name' => 'X'])->assertForbidden();
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/transport/routes/{$foreign->id}")->assertForbidden();
        $this->actingAs($admin, 'sanctum')->postJson("/api/v1/transport/routes/{$foreign->id}/stops", ['name' => 'S', 'sequence_number' => 1])->assertForbidden();
        $this->actingAs($admin, 'sanctum')->getJson("/api/v1/transport/routes/{$foreign->id}/students")->assertForbidden();
    }

    public function test_a_route_with_assigned_students_cannot_be_deleted_but_an_empty_one_deletes_with_its_stops(): void
    {
        $school = School::factory()->create();
        $busy = TransportRoute::factory()->forSchool($school)->create();
        $stop = TransportStop::factory()->forRoute($busy)->create();
        StudentTransportAssignment::factory()->forStudent($this->makeStudent($school))->atStop($stop)->create();
        $empty = TransportRoute::factory()->forSchool($school)->create();
        $emptyStop = TransportStop::factory()->forRoute($empty)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->deleteJson("/api/v1/transport/routes/{$busy->id}")
            ->assertConflict()
            ->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
        $this->actingAs($this->admin($school), 'sanctum')->deleteJson("/api/v1/transport/routes/{$empty->id}")->assertNoContent();
        $this->assertDatabaseMissing('transport_routes', ['id' => $empty->id]);
        $this->assertDatabaseMissing('transport_stops', ['id' => $emptyStop->id]);
    }

    // ── routes: list / show ─────────────────────────────────────────────

    public function test_the_list_carries_counts_and_is_school_scoped_for_viewing_roles(): void
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)->create(['name' => 'Green Park']);
        $stop = TransportStop::factory()->forRoute($route)->create();
        TransportStop::factory()->forRoute($route)->atSequence(2)->create();
        StudentTransportAssignment::factory()->forStudent($this->makeStudent($school))->atStop($stop)->create();
        TransportRoute::factory()->create(['name' => 'Elsewhere']);

        foreach ([UserRole::SchoolAdmin, UserRole::Hod, UserRole::Teacher, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->getJson('/api/v1/transport/routes')
                ->assertOk()
                ->assertJsonCount(1, 'data')
                ->assertJsonPath('data.0.name', 'Green Park')
                ->assertJsonPath('data.0.stops_count', 2)
                ->assertJsonPath('data.0.students_count', 1);
        }
        $staff = User::factory()->role(UserRole::Staff)->forSchool($school)->create();
        $this->actingAs($staff, 'sanctum')->getJson('/api/v1/transport/routes')->assertForbidden();
    }

    public function test_show_returns_the_stops_in_sequence_order_with_rider_counts(): void
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)->create();
        $second = TransportStop::factory()->forRoute($route)->atSequence(2)->create(['name' => 'Central Park', 'pickup_time' => '07:45', 'drop_time' => '15:40']);
        $first = TransportStop::factory()->forRoute($route)->atSequence(1)->create(['name' => 'Lake View']);
        StudentTransportAssignment::factory()->forStudent($this->makeStudent($school))->atStop($second)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->getJson("/api/v1/transport/routes/{$route->id}")
            ->assertOk()
            ->assertJsonPath('stops.0.id', $first->id)
            ->assertJsonPath('stops.0.students_count', 0)
            ->assertJsonPath('stops.1.name', 'Central Park')
            ->assertJsonPath('stops.1.pickup_time', '07:45')
            ->assertJsonPath('stops.1.drop_time', '15:40')
            ->assertJsonPath('stops.1.students_count', 1);
    }

    // ── stops ───────────────────────────────────────────────────────────

    public function test_a_school_admin_can_add_update_and_delete_stops(): void
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)->create();

        $created = $this->actingAs($this->admin($school), 'sanctum')
            ->postJson("/api/v1/transport/routes/{$route->id}/stops", ['name' => 'Lake View', 'sequence_number' => 1, 'pickup_time' => '07:30', 'drop_time' => null]);
        $created->assertCreated()
            ->assertJsonPath('route_id', $route->id)
            ->assertJsonPath('name', 'Lake View')
            ->assertJsonPath('pickup_time', '07:30')
            ->assertJsonPath('drop_time', null)
            ->assertJsonPath('students_count', 0);
        $stopId = $created->json('id');
        $this->assertDatabaseHas('transport_stops', ['id' => $stopId, 'school_id' => $school->id]);

        $this->actingAs($this->admin($school), 'sanctum')
            ->patchJson("/api/v1/transport/stops/{$stopId}", ['name' => 'Lake View Gate', 'sequence_number' => 3])
            ->assertOk()
            ->assertJsonPath('name', 'Lake View Gate')
            ->assertJsonPath('sequence_number', 3);

        $this->actingAs($this->admin($school), 'sanctum')->deleteJson("/api/v1/transport/stops/{$stopId}")->assertNoContent();
        $this->assertDatabaseMissing('transport_stops', ['id' => $stopId]);
    }

    public function test_stop_names_and_sequence_numbers_are_unique_within_a_route_only(): void
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)->create();
        $otherRoute = TransportRoute::factory()->forSchool($school)->create();
        TransportStop::factory()->forRoute($route)->atSequence(1)->create(['name' => 'Lake View']);

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson("/api/v1/transport/routes/{$route->id}/stops", ['name' => 'Lake View', 'sequence_number' => 1])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['name', 'sequence_number']]]);
        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson("/api/v1/transport/routes/{$otherRoute->id}/stops", ['name' => 'Lake View', 'sequence_number' => 1])
            ->assertCreated();
    }

    public function test_stop_times_must_be_hh_mm_and_sequence_at_least_one(): void
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->postJson("/api/v1/transport/routes/{$route->id}/stops", ['name' => 'S', 'sequence_number' => 0, 'pickup_time' => '7am'])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['sequence_number', 'pickup_time']]]);
    }

    public function test_a_stop_with_assigned_students_cannot_be_deleted(): void
    {
        $school = School::factory()->create();
        $stop = TransportStop::factory()->forRoute(TransportRoute::factory()->forSchool($school)->create())->create();
        StudentTransportAssignment::factory()->forStudent($this->makeStudent($school))->atStop($stop)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->deleteJson("/api/v1/transport/stops/{$stop->id}")
            ->assertConflict()
            ->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
    }

    public function test_a_transport_manager_cannot_manage_stops(): void
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)->create();
        $stop = TransportStop::factory()->forRoute($route)->create();
        $manager = User::factory()->role(UserRole::TransportManager)->forSchool($school)->create();

        $this->actingAs($manager, 'sanctum')->postJson("/api/v1/transport/routes/{$route->id}/stops", ['name' => 'S', 'sequence_number' => 2])->assertForbidden();
        $this->actingAs($manager, 'sanctum')->patchJson("/api/v1/transport/stops/{$stop->id}", ['name' => 'X'])->assertForbidden();
        $this->actingAs($manager, 'sanctum')->deleteJson("/api/v1/transport/stops/{$stop->id}")->assertForbidden();
    }

    // ── students on a route ─────────────────────────────────────────────

    public function test_admins_and_the_transport_manager_see_the_riders_in_stop_order_but_a_teacher_does_not(): void
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)->create();
        $second = TransportStop::factory()->forRoute($route)->atSequence(2)->create(['name' => 'Central Park']);
        $first = TransportStop::factory()->forRoute($route)->atSequence(1)->create(['name' => 'Lake View']);
        $laterRider = $this->makeStudent($school);
        $earlyRider = $this->makeStudent($school);
        StudentTransportAssignment::factory()->forStudent($laterRider)->atStop($second)->create();
        StudentTransportAssignment::factory()->forStudent($earlyRider)->atStop($first)->create();
        StudentTransportAssignment::factory()->forStudent($this->makeStudent($school))->create(); // another route

        foreach ([UserRole::SchoolAdmin, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->getJson("/api/v1/transport/routes/{$route->id}/students")
                ->assertOk()
                ->assertJsonCount(2, 'data')
                ->assertJsonPath('data.0.student_id', $earlyRider->id)
                ->assertJsonPath('data.0.stop_name', 'Lake View')
                ->assertJsonPath('data.0.name', $earlyRider->name)
                ->assertJsonPath('data.1.student_id', $laterRider->id)
                ->assertJsonPath('data.1.stop_name', 'Central Park');
        }
        foreach ([UserRole::Teacher, UserRole::Hod, UserRole::Staff] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')->getJson("/api/v1/transport/routes/{$route->id}/students")->assertForbidden();
        }
    }
}

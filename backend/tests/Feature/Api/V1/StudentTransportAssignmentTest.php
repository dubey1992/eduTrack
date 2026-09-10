<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
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

class StudentTransportAssignmentTest extends TestCase
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

    /**
     * @return array{0: School, 1: TransportRoute, 2: TransportStop, 3: Student}
     */
    private function makeRouteWithStop(?int $capacity = 40): array
    {
        $school = School::factory()->create();
        $route = TransportRoute::factory()->forSchool($school)->create(['name' => 'Green Park']);
        if ($capacity !== null) {
            $vehicle = Vehicle::factory()->forSchool($school)->capacity($capacity)->create(['name' => 'Bus 04']);
            $route->update(['vehicle_id' => $vehicle->id]);
        }
        $stop = TransportStop::factory()->forRoute($route)->create(['name' => 'Lake View']);

        return [$school, $route, $stop, $this->makeStudent($school)];
    }

    public function test_a_school_admin_can_assign_a_student_to_a_route_and_stop(): void
    {
        [$school, $route, $stop, $student] = $this->makeRouteWithStop();

        $response = $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $stop->id]);

        $response->assertOk()
            ->assertJsonPath('id', $student->id)
            ->assertJsonPath('transport.route_id', $route->id)
            ->assertJsonPath('transport.route_label', 'Bus 04 - Green Park')
            ->assertJsonPath('transport.vehicle_name', 'Bus 04')
            ->assertJsonPath('transport.stop_id', $stop->id)
            ->assertJsonPath('transport.stop_name', 'Lake View');
        $this->assertDatabaseHas('student_transport_assignments', [
            'student_id' => $student->id, 'school_id' => $school->id, 'route_id' => $route->id, 'transport_stop_id' => $stop->id,
        ]);
    }

    public function test_the_student_list_and_show_carry_the_assignment_or_null(): void
    {
        [$school, $route, $stop, $student] = $this->makeRouteWithStop();
        $walker = $this->makeStudent($school);
        StudentTransportAssignment::factory()->forStudent($student)->atStop($stop)->create();

        $list = $this->actingAs($this->admin($school), 'sanctum')->getJson('/api/v1/students');
        $list->assertOk();
        $rows = collect($list->json('data'))->keyBy('id');
        $this->assertSame($route->id, $rows[$student->id]['transport']['route_id']);
        $this->assertNull($rows[$walker->id]['transport']);

        $this->actingAs($this->admin($school), 'sanctum')
            ->getJson("/api/v1/students/{$walker->id}")
            ->assertOk()
            ->assertJsonPath('transport', null);
    }

    public function test_reassigning_replaces_the_previous_assignment(): void
    {
        [$school, $route, $stop, $student] = $this->makeRouteWithStop();
        $otherStop = TransportStop::factory()->forRoute($route)->atSequence(2)->create(['name' => 'Central Park']);
        StudentTransportAssignment::factory()->forStudent($student)->atStop($stop)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $otherStop->id])
            ->assertOk()
            ->assertJsonPath('transport.stop_name', 'Central Park');
        $this->assertDatabaseCount('student_transport_assignments', 1);
    }

    public function test_a_student_can_be_unassigned(): void
    {
        [$school, , $stop, $student] = $this->makeRouteWithStop();
        StudentTransportAssignment::factory()->forStudent($student)->atStop($stop)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->deleteJson("/api/v1/students/{$student->id}/transport")
            ->assertOk()
            ->assertJsonPath('transport', null);
        $this->assertDatabaseCount('student_transport_assignments', 0);
        // Unassigning a student who has no transport is a harmless no-op.
        $this->actingAs($this->admin($school), 'sanctum')->deleteJson("/api/v1/students/{$student->id}/transport")->assertOk();
    }

    public function test_the_stop_must_belong_to_the_selected_route(): void
    {
        [$school, $route, , $student] = $this->makeRouteWithStop();
        $foreignStop = TransportStop::factory()->forRoute(TransportRoute::factory()->forSchool($school)->create())->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $foreignStop->id])
            ->assertUnprocessable()
            ->assertJsonPath('details.errors.transport_stop_id.0', 'The selected stop is not on the selected route.');
    }

    public function test_a_route_from_another_school_is_rejected(): void
    {
        [$school, , , $student] = $this->makeRouteWithStop();
        $foreignRoute = TransportRoute::factory()->create();
        $foreignStop = TransportStop::factory()->forRoute($foreignRoute)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $foreignRoute->id, 'transport_stop_id' => $foreignStop->id])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['route_id']]]);
    }

    public function test_both_ids_are_required(): void
    {
        [$school, , , $student] = $this->makeRouteWithStop();

        $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", [])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['route_id', 'transport_stop_id']]]);
    }

    public function test_assigning_beyond_the_vehicles_capacity_is_refused(): void
    {
        [$school, $route, $stop, $student] = $this->makeRouteWithStop(capacity: 2);
        StudentTransportAssignment::factory()->forStudent($this->makeStudent($school))->atStop($stop)->create();
        StudentTransportAssignment::factory()->forStudent($this->makeStudent($school))->atStop($stop)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $stop->id])
            ->assertConflict()
            ->assertJsonPath('code', 'ROUTE_CAPACITY_FULL');
        $this->assertDatabaseCount('student_transport_assignments', 2);
    }

    public function test_moving_an_already_assigned_student_between_stops_on_a_full_route_is_allowed(): void
    {
        [$school, $route, $stop, $student] = $this->makeRouteWithStop(capacity: 1);
        $otherStop = TransportStop::factory()->forRoute($route)->atSequence(2)->create();
        StudentTransportAssignment::factory()->forStudent($student)->atStop($stop)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $otherStop->id])
            ->assertOk()
            ->assertJsonPath('transport.stop_id', $otherStop->id);
    }

    public function test_a_route_without_a_vehicle_has_no_capacity_limit(): void
    {
        [$school, $route, $stop, $student] = $this->makeRouteWithStop(capacity: null);
        StudentTransportAssignment::factory()->forStudent($this->makeStudent($school))->atStop($stop)->create();

        $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $stop->id])
            ->assertOk();
    }

    public function test_only_admins_can_assign_or_unassign(): void
    {
        [$school, $route, $stop, $student] = $this->makeRouteWithStop();

        foreach ([UserRole::Hod, UserRole::Teacher, UserRole::Staff, UserRole::TransportManager] as $role) {
            $user = User::factory()->role($role)->forSchool($school)->create();
            $this->actingAs($user, 'sanctum')
                ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $stop->id])
                ->assertForbidden();
            $this->actingAs($user, 'sanctum')->deleteJson("/api/v1/students/{$student->id}/transport")->assertForbidden();
        }
    }

    public function test_a_school_admin_cannot_assign_another_schools_student(): void
    {
        [$school, $route, $stop] = $this->makeRouteWithStop();
        $foreignStudent = $this->makeStudent(School::factory()->create());

        $this->actingAs($this->admin($school), 'sanctum')
            ->putJson("/api/v1/students/{$foreignStudent->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $stop->id])
            ->assertForbidden();
    }

    public function test_a_super_admin_can_assign_any_student(): void
    {
        [, $route, $stop, $student] = $this->makeRouteWithStop();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')
            ->putJson("/api/v1/students/{$student->id}/transport", ['route_id' => $route->id, 'transport_stop_id' => $stop->id])
            ->assertOk();
    }
}

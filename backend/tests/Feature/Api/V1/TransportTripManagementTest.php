<?php

namespace Tests\Feature\Api\V1;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\ClassSection;
use App\Models\Driver;
use App\Models\Holiday;
use App\Models\School;
use App\Models\SchoolClass;
use App\Models\Student;
use App\Models\StudentTransportAssignment;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\TransportTrip;
use App\Models\TransportTripRider;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Illuminate\Support\Carbon;
use Tests\TestCase;

class TransportTripManagementTest extends TestCase
{
    use RefreshDatabase;

    private const string TRIPS = '/api/v1/transport/trips';

    protected function setUp(): void
    {
        parent::setUp();
        // A plain Wednesday, so "today" is always a working day unless a test says otherwise.
        Carbon::setTestNow('2026-09-09 07:30:00');
    }

    protected function tearDown(): void
    {
        Carbon::setTestNow();
        parent::tearDown();
    }

    /**
     * A ready route (Bus 04 + Sanjay, two stops) with three active riders
     * (two at Lake View, one at Central Park) and one inactive student who
     * must be left off the trip.
     *
     * @return array{school: School, route: TransportRoute, stops: array<int, TransportStop>, students: array<int, Student>, manager: User, admin: User, teacher: User}
     */
    private function makeReadyRoute(?School $school = null): array
    {
        $school ??= School::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($school)->capacity(30)->create(['name' => 'Bus 04']);
        $driver = Driver::factory()->forSchool($school)->create(['name' => 'Sanjay Patel']);
        $route = TransportRoute::factory()->forSchool($school)->withVehicle($vehicle)->withDriver($driver)->create(['name' => 'Green Park']);
        $lakeView = TransportStop::factory()->forRoute($route)->atSequence(1)->create(['name' => 'Lake View']);
        $centralPark = TransportStop::factory()->forRoute($route)->atSequence(2)->create(['name' => 'Central Park']);

        $year = AcademicYear::factory()->forSchool($school)->create();
        $section = ClassSection::factory()->forClass(SchoolClass::factory()->forAcademicYear($year)->create())->create();
        $arjun = Student::factory()->forSection($section)->create(['first_name' => 'Arjun', 'last_name' => 'Kumar']);
        $aarav = Student::factory()->forSection($section)->create(['first_name' => 'Aarav', 'last_name' => 'Mehta']);
        $meera = Student::factory()->forSection($section)->create(['first_name' => 'Meera', 'last_name' => 'Singh']);
        $inactive = Student::factory()->forSection($section)->inactive()->create();
        foreach ([[$arjun, $lakeView], [$aarav, $lakeView], [$meera, $centralPark], [$inactive, $lakeView]] as [$student, $stop]) {
            StudentTransportAssignment::factory()->forStudent($student)->atStop($stop)->create();
        }

        return [
            'school' => $school,
            'route' => $route,
            'stops' => [$lakeView, $centralPark],
            'students' => [$arjun, $aarav, $meera],
            'manager' => User::factory()->role(UserRole::TransportManager)->forSchool($school)->create(),
            'admin' => User::factory()->role(UserRole::SchoolAdmin)->forSchool($school)->create(),
            'teacher' => User::factory()->role(UserRole::Teacher)->forSchool($school)->create(),
        ];
    }

    private function startTrip(User $actor, TransportRoute $route, string $direction = 'pickup')
    {
        return $this->actingAs($actor, 'sanctum')->postJson(self::TRIPS, ['route_id' => $route->id, 'direction' => $direction]);
    }

    // ── start ───────────────────────────────────────────────────────────

    public function test_a_transport_manager_can_start_a_pickup_trip_with_the_routes_active_riders(): void
    {
        $f = $this->makeReadyRoute();

        $response = $this->startTrip($f['manager'], $f['route']);

        $response->assertCreated()
            ->assertJsonPath('route_label', 'Bus 04 - Green Park')
            ->assertJsonPath('vehicle_name', 'Bus 04')
            ->assertJsonPath('driver_name', 'Sanjay Patel')
            ->assertJsonPath('trip_date', '2026-09-09')
            ->assertJsonPath('direction', 'pickup')
            ->assertJsonPath('status', 'in_progress')
            ->assertJsonPath('current_stop_id', null)
            ->assertJsonPath('started_by_name', $f['manager']->name)
            ->assertJsonPath('riders_count', 3)
            ->assertJsonPath('pending_count', 3)
            ->assertJsonPath('boarded_count', 0)
            ->assertJsonPath('stops_left', 2)
            ->assertJsonPath('stops.0.name', 'Lake View')
            ->assertJsonPath('stops.0.reached', false)
            ->assertJsonPath('events.0.type', 'started')
            ->assertJsonPath('events.0.note', 'Trip started with 3 students expected');

        $riders = collect($response->json('riders'));
        $this->assertSame(['Aarav Mehta', 'Arjun Kumar', 'Meera Singh'], $riders->pluck('name')->sort()->values()->all());
        $this->assertSame('Central Park', $riders->firstWhere('name', 'Meera Singh')['stop_name']);
        $this->assertDatabaseCount('transport_trip_riders', 3);
    }

    public function test_school_and_super_admins_can_start_trips_but_viewing_roles_cannot(): void
    {
        $f = $this->makeReadyRoute();
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->startTrip($f['admin'], $f['route'])->assertCreated();
        $this->actingAs($f['admin'], 'sanctum')->postJson(self::TRIPS.'/'.TransportTrip::first()->id.'/cancel')->assertOk();
        $this->startTrip($superAdmin, $f['route'])->assertCreated();

        foreach ([UserRole::Hod, UserRole::Teacher, UserRole::Staff] as $role) {
            $user = User::factory()->role($role)->forSchool($f['school'])->create();
            $this->startTrip($user, $f['route'])->assertForbidden();
        }
    }

    public function test_a_route_from_another_school_is_rejected(): void
    {
        $f = $this->makeReadyRoute();
        $foreign = $this->makeReadyRoute();

        $this->startTrip($f['manager'], $foreign['route'])
            ->assertUnprocessable()
            ->assertJsonPath('details.errors.route_id.0', 'The selected route does not belong to this school.');
    }

    public function test_the_direction_is_required_and_validated(): void
    {
        $f = $this->makeReadyRoute();

        $this->startTrip($f['manager'], $f['route'], 'evening')
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['direction']]]);
    }

    public function test_a_route_without_an_active_vehicle_and_driver_cannot_start(): void
    {
        $f = $this->makeReadyRoute();
        $f['route']->update(['driver_id' => null]);
        $this->startTrip($f['manager'], $f['route'])->assertConflict()->assertJsonPath('code', 'ROUTE_NOT_READY');

        $driver = Driver::factory()->forSchool($f['school'])->inactive()->create();
        $f['route']->update(['driver_id' => $driver->id]);
        $this->startTrip($f['manager'], $f['route'])->assertConflict()->assertJsonPath('code', 'ROUTE_NOT_READY');

        $f['route']->update(['driver_id' => Driver::factory()->forSchool($f['school'])->create()->id, 'status' => 'inactive']);
        $this->startTrip($f['manager'], $f['route'])->assertConflict()->assertJsonPath('code', 'ROUTE_NOT_READY');
    }

    public function test_trips_do_not_run_on_holidays_or_weekends(): void
    {
        $f = $this->makeReadyRoute();
        Holiday::factory()->forSchool($f['school'])->onDates('2026-09-09')->create();
        $this->startTrip($f['manager'], $f['route'])->assertConflict()->assertJsonPath('code', 'TRIP_ON_NON_WORKING_DAY');

        Holiday::query()->delete();
        Carbon::setTestNow('2026-09-12 07:30:00'); // Saturday
        $this->startTrip($f['manager'], $f['route'])->assertConflict()->assertJsonPath('code', 'TRIP_ON_NON_WORKING_DAY');
    }

    public function test_only_one_trip_per_route_can_be_in_progress_and_a_direction_runs_once_a_day(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->assertCreated()->json('id');

        $this->startTrip($f['manager'], $f['route'], 'drop')->assertConflict()->assertJsonPath('code', 'TRIP_ALREADY_IN_PROGRESS');

        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/end")->assertOk();
        $this->startTrip($f['manager'], $f['route'])->assertConflict()->assertJsonPath('code', 'TRIP_ALREADY_EXISTS');
        $this->startTrip($f['manager'], $f['route'], 'drop')->assertCreated()->assertJsonPath('direction', 'drop');
    }

    public function test_a_cancelled_trip_can_be_run_again_the_same_day(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');

        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/cancel")
            ->assertOk()
            ->assertJsonPath('status', 'cancelled')
            ->assertJsonPath('events.1.type', 'cancelled');
        $this->startTrip($f['manager'], $f['route'])->assertCreated();
    }

    public function test_a_route_with_no_riders_still_starts(): void
    {
        $f = $this->makeReadyRoute();
        StudentTransportAssignment::query()->delete();

        $this->startTrip($f['manager'], $f['route'])->assertCreated()->assertJsonPath('riders_count', 0)->assertJsonPath('stops_left', 2);
    }

    // ── stops ───────────────────────────────────────────────────────────

    public function test_reaching_a_stop_updates_the_trip_and_the_timeline(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        [$lakeView, $centralPark] = $f['stops'];

        $response = $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/stops/{$lakeView->id}/reached");

        $response->assertOk()
            ->assertJsonPath('current_stop_id', $lakeView->id)
            ->assertJsonPath('current_stop_name', 'Lake View')
            ->assertJsonPath('stops.0.reached', true)
            ->assertJsonPath('stops.1.reached', false)
            ->assertJsonPath('stops_left', 1)
            ->assertJsonPath('events.1.type', 'stop_reached')
            ->assertJsonPath('events.1.stop_name', 'Lake View');

        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/stops/{$centralPark->id}/reached")
            ->assertOk()
            ->assertJsonPath('stops_left', 0);
    }

    public function test_a_stop_from_another_route_cannot_be_reached_and_a_teacher_cannot_reach_stops(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        $otherStop = TransportStop::factory()->forRoute(TransportRoute::factory()->forSchool($f['school'])->create())->create();

        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/stops/{$otherStop->id}/reached")
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['stop']]]);
        $this->actingAs($f['teacher'], 'sanctum')->postJson(self::TRIPS."/{$trip}/stops/{$f['stops'][0]->id}/reached")
            ->assertForbidden();
    }

    // ── riders ──────────────────────────────────────────────────────────

    public function test_riders_board_at_the_current_stop_and_are_dropped_with_timestamps_and_events(): void
    {
        $f = $this->makeReadyRoute();
        [$arjun] = $f['students'];
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/stops/{$f['stops'][0]->id}/reached");

        $boarded = $this->actingAs($f['manager'], 'sanctum')
            ->patchJson(self::TRIPS."/{$trip}/riders/{$arjun->id}", ['status' => 'boarded']);
        $boarded->assertOk()->assertJsonPath('boarded_count', 1)->assertJsonPath('pending_count', 2);
        $rider = collect($boarded->json('riders'))->firstWhere('student_id', $arjun->id);
        $this->assertSame('boarded', $rider['status']);
        $this->assertNotNull($rider['boarded_at']);
        $this->assertNull($rider['dropped_at']);
        $event = collect($boarded->json('events'))->last();
        $this->assertSame(['boarded', 'Lake View', 'Arjun Kumar'], [$event['type'], $event['stop_name'], $event['student_name']]);

        $dropped = $this->actingAs($f['manager'], 'sanctum')
            ->patchJson(self::TRIPS."/{$trip}/riders/{$arjun->id}", ['status' => 'dropped']);
        $dropped->assertOk()->assertJsonPath('dropped_count', 1)->assertJsonPath('boarded_count', 0);
        $this->assertNotNull(collect($dropped->json('riders'))->firstWhere('student_id', $arjun->id)['dropped_at']);
    }

    public function test_a_pending_rider_can_be_marked_absent(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');

        $this->actingAs($f['manager'], 'sanctum')
            ->patchJson(self::TRIPS."/{$trip}/riders/{$f['students'][2]->id}", ['status' => 'absent'])
            ->assertOk()
            ->assertJsonPath('absent_count', 1)
            ->assertJsonPath('pending_count', 2);
    }

    public function test_invalid_rider_transitions_are_refused(): void
    {
        $f = $this->makeReadyRoute();
        [$arjun, $aarav] = $f['students'];
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        $patch = fn (Student $s, string $status) => $this->actingAs($f['manager'], 'sanctum')
            ->patchJson(self::TRIPS."/{$trip}/riders/{$s->id}", ['status' => $status]);

        $patch($arjun, 'dropped')->assertConflict()->assertJsonPath('code', 'INVALID_RIDER_STATUS_CHANGE');   // never boarded
        $patch($arjun, 'boarded')->assertOk();
        $patch($arjun, 'boarded')->assertConflict()->assertJsonPath('code', 'INVALID_RIDER_STATUS_CHANGE');   // twice
        $patch($arjun, 'absent')->assertConflict();                                                             // on board
        $patch($arjun, 'dropped')->assertOk();
        $patch($arjun, 'boarded')->assertConflict();                                                            // already dropped
        $patch($aarav, 'absent')->assertOk();
        $patch($aarav, 'boarded')->assertConflict();                                                            // absent stays absent
        $patch($aarav, 'pending')->assertUnprocessable();
    }

    public function test_a_student_who_is_not_on_the_trip_is_rejected(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        $walker = Student::factory()->forSection($f['students'][0]->classSection)->create();

        $this->actingAs($f['manager'], 'sanctum')
            ->patchJson(self::TRIPS."/{$trip}/riders/{$walker->id}", ['status' => 'boarded'])
            ->assertUnprocessable()
            ->assertJsonStructure(['details' => ['errors' => ['student']]]);
    }

    public function test_a_teacher_cannot_change_riders(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');

        $this->actingAs($f['teacher'], 'sanctum')
            ->patchJson(self::TRIPS."/{$trip}/riders/{$f['students'][0]->id}", ['status' => 'boarded'])
            ->assertForbidden();
    }

    // ── end / cancel ────────────────────────────────────────────────────

    public function test_ending_refuses_while_someone_is_on_board_then_marks_the_rest_absent(): void
    {
        $f = $this->makeReadyRoute();
        [$arjun, $aarav] = $f['students'];
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        $patch = fn (Student $s, string $status) => $this->actingAs($f['manager'], 'sanctum')
            ->patchJson(self::TRIPS."/{$trip}/riders/{$s->id}", ['status' => $status]);
        $patch($arjun, 'boarded');
        $patch($aarav, 'boarded');
        $patch($aarav, 'dropped');

        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/end")
            ->assertConflict()
            ->assertJsonPath('code', 'TRIP_RIDERS_ON_BOARD')
            ->assertJsonPath('message', '1 student is still on board. Drop them off before ending the trip.');

        $patch($arjun, 'dropped');
        $ended = $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/end");
        $ended->assertOk()
            ->assertJsonPath('status', 'completed')
            ->assertJsonPath('dropped_count', 2)
            ->assertJsonPath('absent_count', 1)   // Meera never boarded
            ->assertJsonPath('pending_count', 0);
        $this->assertNotNull($ended->json('ended_at'));
        $this->assertSame('Trip completed; 1 marked absent', collect($ended->json('events'))->last()['note']);
    }

    public function test_nothing_can_be_changed_on_a_finished_trip(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/cancel")->assertOk();

        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/stops/{$f['stops'][0]->id}/reached")
            ->assertConflict()->assertJsonPath('code', 'TRIP_NOT_IN_PROGRESS');
        $this->actingAs($f['manager'], 'sanctum')->patchJson(self::TRIPS."/{$trip}/riders/{$f['students'][0]->id}", ['status' => 'boarded'])
            ->assertConflict()->assertJsonPath('code', 'TRIP_NOT_IN_PROGRESS');
        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/end")
            ->assertConflict()->assertJsonPath('code', 'TRIP_NOT_IN_PROGRESS');
    }

    public function test_only_managing_roles_can_end_or_cancel(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');

        $this->actingAs($f['teacher'], 'sanctum')->postJson(self::TRIPS."/{$trip}/end")->assertForbidden();
        $this->actingAs($f['teacher'], 'sanctum')->postJson(self::TRIPS."/{$trip}/cancel")->assertForbidden();
        $foreignAdmin = User::factory()->role(UserRole::SchoolAdmin)->forSchool(School::factory()->create())->create();
        $this->actingAs($foreignAdmin, 'sanctum')->postJson(self::TRIPS."/{$trip}/end")->assertForbidden();
    }

    // ── list / show ─────────────────────────────────────────────────────

    public function test_trips_are_listed_newest_first_with_counts_scoped_to_the_school_and_filterable(): void
    {
        $f = $this->makeReadyRoute();
        $foreign = $this->makeReadyRoute();
        $this->startTrip($foreign['manager'], $foreign['route'])->assertCreated();
        $first = $this->startTrip($f['manager'], $f['route'])->json('id');
        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$first}/end")->assertOk();
        Carbon::setTestNow('2026-09-09 15:00:00');
        $second = $this->startTrip($f['manager'], $f['route'], 'drop')->json('id');

        foreach ([$f['admin'], $f['manager'], $f['teacher'], User::factory()->role(UserRole::Hod)->forSchool($f['school'])->create()] as $viewer) {
            $this->actingAs($viewer, 'sanctum')->getJson(self::TRIPS)
                ->assertOk()
                ->assertJsonCount(2, 'data')
                ->assertJsonPath('data.0.id', $second)
                ->assertJsonPath('data.0.direction', 'drop')
                ->assertJsonPath('data.0.riders_count', 3)
                ->assertJsonPath('data.1.status', 'completed');
        }
        $this->actingAs($f['manager'], 'sanctum')->getJson(self::TRIPS.'?status=in_progress')->assertOk()->assertJsonCount(1, 'data');
        $this->actingAs($f['manager'], 'sanctum')->getJson(self::TRIPS."?route_id={$f['route']->id}&date=2026-09-08")->assertOk()->assertJsonCount(0, 'data');

        $staff = User::factory()->role(UserRole::Staff)->forSchool($f['school'])->create();
        $this->actingAs($staff, 'sanctum')->getJson(self::TRIPS)->assertForbidden();
        $this->actingAs($f['manager'], 'sanctum')->getJson(self::TRIPS.'/'.TransportTrip::where('school_id', $foreign['school']->id)->first()->id)->assertForbidden();
    }

    public function test_a_super_admin_sees_every_school_and_can_filter_by_school(): void
    {
        $f = $this->makeReadyRoute();
        $foreign = $this->makeReadyRoute();
        $this->startTrip($f['manager'], $f['route']);
        $this->startTrip($foreign['manager'], $foreign['route']);
        $superAdmin = User::factory()->role(UserRole::SuperAdmin)->create(['school_id' => null]);

        $this->actingAs($superAdmin, 'sanctum')->getJson(self::TRIPS)->assertOk()->assertJsonCount(2, 'data');
        $this->actingAs($superAdmin, 'sanctum')->getJson(self::TRIPS."?school_id={$f['school']->id}")->assertOk()->assertJsonCount(1, 'data');
    }

    // ── history protection ──────────────────────────────────────────────

    public function test_vehicles_drivers_and_routes_with_trip_history_cannot_be_deleted(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/end")->assertOk();
        $route = $f['route']->fresh();
        StudentTransportAssignment::query()->delete();
        $route->update(['vehicle_id' => null, 'driver_id' => null]);

        $admin = $f['admin'];
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/transport/vehicles/{$f['route']->vehicle_id}")->assertConflict()->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/transport/drivers/{$f['route']->driver_id}")->assertConflict()->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
        $this->actingAs($admin, 'sanctum')->deleteJson("/api/v1/transport/routes/{$route->id}")->assertConflict()->assertJsonPath('code', 'HAS_DEPENDENT_RECORDS');
    }

    public function test_a_stop_can_still_be_removed_after_trips_because_riders_keep_its_name(): void
    {
        $f = $this->makeReadyRoute();
        $trip = $this->startTrip($f['manager'], $f['route'])->json('id');
        $this->actingAs($f['manager'], 'sanctum')->postJson(self::TRIPS."/{$trip}/end")->assertOk();
        StudentTransportAssignment::query()->delete();

        $this->actingAs($f['admin'], 'sanctum')->deleteJson("/api/v1/transport/stops/{$f['stops'][0]->id}")->assertNoContent();

        $rider = TransportTripRider::where('student_id', $f['students'][0]->id)->first();
        $this->assertNull($rider->stop_id);
        $this->assertSame('Lake View', $rider->stop_name);
        $this->actingAs($f['manager'], 'sanctum')->getJson(self::TRIPS."/{$trip}")
            ->assertOk()
            ->assertJsonPath('stops_left', 1);
    }
}

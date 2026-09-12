<?php

namespace App\Services;

use App\Enums\StudentStatus;
use App\Enums\TransportStatus;
use App\Enums\TripDirection;
use App\Enums\TripEventType;
use App\Enums\TripRiderStatus;
use App\Enums\TripStatus;
use App\Enums\UserRole;
use App\Exceptions\TripRuleException;
use App\Models\Student;
use App\Models\StudentTransportAssignment;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\TransportTrip;
use App\Models\TransportTripEvent;
use App\Models\TransportTripRider;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * The live trip workflow (decided 2026-09-10): a trip is one run of a route
 * today in one direction; it needs an active route with a vehicle and
 * driver, a working day, and no other trip of that route in progress. Its
 * riders are the route's active assigned students, snapshotted at start.
 */
class TransportTripService
{
    private const array LIST_RELATIONS = ['route', 'vehicle', 'driver', 'currentStop'];

    private const array DETAIL_RELATIONS = [
        'route.stops', 'vehicle', 'driver', 'currentStop', 'startedBy',
        'riders.student.classSection.schoolClass', 'events.recordedBy',
    ];

    public function __construct(private readonly HolidayService $holidayService) {}

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return TransportTrip::query()
            ->with(self::LIST_RELATIONS)
            ->withCount('riders')
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id),
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
            ->when($filters['route_id'] ?? null, fn ($query, $routeId) => $query->where('route_id', $routeId))
            ->when($filters['date'] ?? null, fn ($query, $date) => $query->where('trip_date', $date))
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            ->orderByDesc('trip_date')
            ->orderByDesc('started_at')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    public function detail(TransportTrip $trip): TransportTrip
    {
        return $trip->load(self::DETAIL_RELATIONS);
    }

    public function start(TransportRoute $route, TripDirection $direction, User $actor): TransportTrip
    {
        $route->loadMissing(['vehicle', 'driver']);
        $today = now()->toDateString();

        if (! $route->isActive() || $route->vehicle === null || $route->driver === null
            || $route->vehicle->status !== TransportStatus::Active || $route->driver->status !== TransportStatus::Active) {
            throw TripRuleException::routeNotReady($route->name);
        }
        if (! $this->holidayService->isWorkingDay($route->school_id, $today)) {
            throw TripRuleException::nonWorkingDay();
        }
        $this->assertRouteIsFree($route, $direction, $today);

        return DB::transaction(function () use ($route, $direction, $actor, $today) {
            // Lock the route so two taps on "Start Trip" cannot both get past
            // the checks and create two live trips for the same bus.
            TransportRoute::whereKey($route->id)->lockForUpdate()->first();
            $this->assertRouteIsFree($route, $direction, $today);

            $trip = TransportTrip::create([
                'school_id' => $route->school_id,
                'route_id' => $route->id,
                'vehicle_id' => $route->vehicle_id,
                'driver_id' => $route->driver_id,
                'trip_date' => $today,
                'direction' => $direction,
                'status' => TripStatus::InProgress,
                'started_by' => $actor->id,
                'started_at' => now(),
            ]);

            $assignments = StudentTransportAssignment::query()
                ->where('route_id', $route->id)
                ->with(['student', 'stop'])
                ->get()
                ->filter(fn (StudentTransportAssignment $a) => $a->student->status === StudentStatus::Active);

            foreach ($assignments as $assignment) {
                TransportTripRider::create([
                    'trip_id' => $trip->id,
                    'student_id' => $assignment->student_id,
                    'stop_id' => $assignment->stop->id,
                    'stop_name' => $assignment->stop->name,
                    'stop_sequence_number' => $assignment->stop->sequence_number,
                    'status' => TripRiderStatus::Pending,
                ]);
            }

            $this->record($trip, TripEventType::Started, $actor, note: "Trip started with {$assignments->count()} students expected");

            return $this->detail($trip);
        });
    }

    /**
     * One trip per route at a time, and one run per direction per day unless
     * the previous run was cancelled (decided 2026-09-11).
     */
    private function assertRouteIsFree(TransportRoute $route, TripDirection $direction, string $today): void
    {
        if ($route->trips()->where('status', TripStatus::InProgress)->exists()) {
            throw TripRuleException::alreadyInProgress($route->name);
        }

        $alreadyRun = $route->trips()
            ->where('trip_date', $today)
            ->where('direction', $direction)
            ->where('status', '!=', TripStatus::Cancelled)
            ->exists();

        if ($alreadyRun) {
            throw TripRuleException::alreadyExists($route->name, $direction->value);
        }
    }

    public function reachStop(TransportTrip $trip, TransportStop $stop, User $actor): TransportTrip
    {
        $this->assertInProgress($trip);

        DB::transaction(function () use ($trip, $stop, $actor) {
            $this->assertInProgress($this->lockTrip($trip));
            $trip->update(['current_stop_id' => $stop->id]);
            $this->record($trip, TripEventType::StopReached, $actor, stop: $stop);
        });

        return $this->detail($trip->fresh());
    }

    public function updateRider(TransportTrip $trip, Student $student, TripRiderStatus $status, User $actor): TransportTrip
    {
        $this->assertInProgress($trip);

        $rider = $trip->riders()->where('student_id', $student->id)->firstOrFail();
        $this->assertTransition($rider, $status);

        DB::transaction(function () use ($trip, $rider, $status, $actor, $student) {
            $this->assertInProgress($this->lockTrip($trip));
            // Re-read under a lock: two quick taps must not board the same
            // student twice or race a concurrent drop.
            $rider = $trip->riders()->whereKey($rider->id)->lockForUpdate()->firstOrFail();
            $this->assertTransition($rider, $status);

            $rider->update([
                'status' => $status,
                'boarded_at' => $status === TripRiderStatus::Boarded ? now() : $rider->boarded_at,
                'dropped_at' => $status === TripRiderStatus::Dropped ? now() : $rider->dropped_at,
            ]);
            $type = match ($status) {
                TripRiderStatus::Boarded => TripEventType::Boarded,
                TripRiderStatus::Dropped => TripEventType::Dropped,
                TripRiderStatus::Absent => TripEventType::Absent,
                TripRiderStatus::Pending => throw TripRuleException::invalidRiderChange($rider->status->value, 'pending'),
            };
            $this->record($trip, $type, $actor, stop: $trip->currentStop, student: $student);
        });

        return $this->detail($trip->fresh());
    }

    /**
     * Riders still pending are marked absent; anyone still on board blocks
     * the end (decided 2026-09-10).
     */
    public function end(TransportTrip $trip, User $actor): TransportTrip
    {
        $this->assertInProgress($trip);

        $this->assertNobodyOnBoard($trip);

        DB::transaction(function () use ($trip, $actor) {
            $this->assertInProgress($this->lockTrip($trip));
            // Someone may have boarded between the check above and here.
            $this->assertNobodyOnBoard($trip, lock: true);

            $markedAbsent = $trip->riders()
                ->where('status', TripRiderStatus::Pending->value)
                ->update(['status' => TripRiderStatus::Absent->value]);
            $trip->update(['status' => TripStatus::Completed, 'ended_at' => now()]);
            $note = $markedAbsent > 0 ? "Trip completed; {$markedAbsent} marked absent" : 'Trip completed';
            $this->record($trip, TripEventType::Completed, $actor, note: $note);
        });

        return $this->detail($trip->fresh());
    }

    public function cancel(TransportTrip $trip, User $actor): TransportTrip
    {
        $this->assertInProgress($trip);

        DB::transaction(function () use ($trip, $actor) {
            $this->assertInProgress($this->lockTrip($trip));
            $trip->update(['status' => TripStatus::Cancelled, 'ended_at' => now()]);
            $this->record($trip, TripEventType::Cancelled, $actor, note: 'Trip cancelled');
        });

        return $this->detail($trip->fresh());
    }

    /**
     * Re-reads the trip with a row lock so the guards below see (and hold)
     * the state the write is about to be based on.
     */
    private function lockTrip(TransportTrip $trip): TransportTrip
    {
        return TransportTrip::whereKey($trip->getKey())->lockForUpdate()->firstOrFail();
    }

    private function assertTransition(TransportTripRider $rider, TripRiderStatus $status): void
    {
        if (! $rider->status->canBecome($status)) {
            throw TripRuleException::invalidRiderChange($rider->status->value, $status->value);
        }
    }

    private function assertNobodyOnBoard(TransportTrip $trip, bool $lock = false): void
    {
        $riders = $trip->riders()->where('status', TripRiderStatus::Boarded);
        $onBoard = $lock ? $riders->lockForUpdate()->count() : $riders->count();

        if ($onBoard > 0) {
            throw TripRuleException::ridersOnBoard($onBoard);
        }
    }

    private function assertInProgress(TransportTrip $trip): void
    {
        if (! $trip->isInProgress()) {
            throw TripRuleException::notInProgress();
        }
    }

    private function record(
        TransportTrip $trip,
        TripEventType $type,
        User $actor,
        ?TransportStop $stop = null,
        ?Student $student = null,
        ?string $note = null,
    ): void {
        TransportTripEvent::create([
            'school_id' => $trip->school_id,
            'trip_id' => $trip->id,
            'type' => $type,
            'stop_id' => $stop?->id,
            'stop_name' => $stop?->name,
            'student_id' => $student?->id,
            'student_name' => $student?->name,
            'recorded_by' => $actor->id,
            'recorded_at' => Carbon::now(),
            'note' => $note,
        ]);
    }
}

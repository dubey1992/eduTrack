<?php

namespace App\Services\Reports;

use App\Enums\TripRiderStatus;
use App\Enums\TripStatus;
use App\Models\TransportRoute;
use App\Models\TransportTrip;
use App\Models\TransportTripRider;
use App\Support\Reports\CombinesTotals;
use App\Support\Reports\ReportRange;
use Illuminate\Support\Collection;

/**
 * How each bus route actually ran over a range: trips completed, days it
 * never left, and what happened to the children on it.
 *
 * "Days not run" is measured against the school's working days, so a route
 * is not marked as having missed a holiday nobody expected it to run on.
 */
class TransportUsageReport implements CombinesTotals
{
    /**
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    public function build(ReportRange $range, array $filters): array
    {
        $routes = TransportRoute::query()
            ->where('school_id', $range->schoolId)
            ->with(['vehicle', 'driver'])
            ->orderBy('name')
            ->get();

        $trips = $this->tripsByRoute($range);
        $riders = $this->ridersByRoute($range);

        $rows = $routes->map(function (TransportRoute $route) use ($trips, $riders, $range) {
            $routeTrips = $trips->get($route->id, collect());
            $completed = (int) $routeTrips->where('status_value', TripStatus::Completed->value)->sum('total');
            $cancelled = (int) $routeTrips->where('status_value', TripStatus::Cancelled->value)->sum('total');
            $inProgress = (int) $routeTrips->where('status_value', TripStatus::InProgress->value)->sum('total');
            $daysRun = (int) ($routeTrips->max('days') ?? 0);
            $counts = $riders->get($route->id, collect());

            return [
                'route_id' => $route->id,
                'route' => $route->name,
                'vehicle' => $route->vehicle?->name,
                'driver' => $route->driver?->name,
                'working_days' => $range->workingDayCount(),
                'days_run' => $daysRun,
                // Working days on which this route never started a trip at
                // all - the figure that says a bus quietly stopped running.
                'days_not_run' => max(0, $range->workingDayCount() - $daysRun),
                'trips_completed' => $completed,
                'trips_cancelled' => $cancelled,
                'trips_in_progress' => $inProgress,
                'riders_boarded' => (int) $counts->get(TripRiderStatus::Boarded->value, 0),
                'riders_dropped' => (int) $counts->get(TripRiderStatus::Dropped->value, 0),
                'riders_absent' => (int) $counts->get(TripRiderStatus::Absent->value, 0),
            ];
        });

        return [
            'range' => $range->toArray(),
            'rows' => $rows->all(),
            'totals' => [
                'routes' => $rows->count(),
                'working_days' => $range->workingDayCount(),
                'trips_completed' => (int) $rows->sum('trips_completed'),
                'trips_cancelled' => (int) $rows->sum('trips_cancelled'),
                'riders_boarded' => (int) $rows->sum('riders_boarded'),
                'riders_absent' => (int) $rows->sum('riders_absent'),
            ],
        ];
    }

    /**
     * @return array<int, string>
     */
    public function headings(): array
    {
        return ['Route', 'Vehicle', 'Driver', 'Working days', 'Days run', 'Days not run', 'Trips completed', 'Trips cancelled', 'Boarded', 'Dropped', 'Absent'];
    }

    /**
     * @param  array<string, mixed>  $report
     * @return array<int, array<int, mixed>>
     */
    public function csvRows(array $report): array
    {
        return array_map(fn (array $row) => [
            $row['route'],
            $row['vehicle'],
            $row['driver'],
            $row['working_days'],
            $row['days_run'],
            $row['days_not_run'],
            $row['trips_completed'],
            $row['trips_cancelled'],
            $row['riders_boarded'],
            $row['riders_dropped'],
            $row['riders_absent'],
        ], $report['rows']);
    }

    /**
     * Trip counts per route and status, plus how many distinct days the route
     * ran at all.
     *
     * @return Collection<int, Collection<int, object>>
     */
    private function tripsByRoute(ReportRange $range): Collection
    {
        [$from, $to] = $range->bounds();

        return TransportTrip::query()
            ->where('school_id', $range->schoolId)
            ->whereBetween('trip_date', [$from, $to])
            ->selectRaw('route_id, status as status_value, COUNT(*) as total, COUNT(DISTINCT trip_date) as days')
            ->groupBy('route_id', 'status')
            ->get()
            ->groupBy('route_id');
    }

    /**
     * @return Collection<int, Collection<string, int>>
     */
    private function ridersByRoute(ReportRange $range): Collection
    {
        [$from, $to] = $range->bounds();

        return TransportTripRider::query()
            ->join('transport_trips', 'transport_trips.id', '=', 'transport_trip_riders.trip_id')
            ->where('transport_trips.school_id', $range->schoolId)
            ->whereBetween('transport_trips.trip_date', [$from, $to])
            ->selectRaw('transport_trips.route_id as route_id, transport_trip_riders.status as status_value, COUNT(*) as total')
            ->groupBy('transport_trips.route_id', 'transport_trip_riders.status')
            ->get()
            ->groupBy('route_id')
            ->map(fn (Collection $rows) => $rows->pluck('total', 'status_value'));
    }

    /**
     * @param  array<int, array<string, mixed>>  $branchTotals
     * @return array<string, mixed>
     */
    public function combineTotals(array $branchTotals): array
    {
        $sum = fn (string $key) => (int) array_sum(array_column($branchTotals, $key));

        return [
            'branches' => count($branchTotals),
            'routes' => $sum('routes'),
            'trips_completed' => $sum('trips_completed'),
            'trips_cancelled' => $sum('trips_cancelled'),
            'riders_boarded' => $sum('riders_boarded'),
            'riders_absent' => $sum('riders_absent'),
        ];
    }
}

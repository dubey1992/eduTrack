<?php

namespace App\Services;

use App\Enums\TransportStatus;
use App\Enums\UserRole;
use App\Exceptions\HasDependentRecordsException;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;

class TransportRouteService
{
    private const array RELATIONS = ['school', 'vehicle', 'driver'];

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return TransportRoute::query()
            ->with(self::RELATIONS)
            ->withCount(['stops', 'assignments'])
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id),
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            ->orderBy('name')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * The route with its ordered stops (each with its rider count).
     */
    public function detail(TransportRoute $route): TransportRoute
    {
        return $route
            ->load([...self::RELATIONS, 'stops' => fn ($query) => $query->withCount('assignments')])
            ->loadCount(['stops', 'assignments']);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): TransportRoute
    {
        if ($actor->role !== UserRole::SuperAdmin) {
            $data['school_id'] = $actor->school_id;
        }

        return TransportRoute::create([...$data, 'status' => TransportStatus::Active]);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(TransportRoute $route, array $data): TransportRoute
    {
        $route->update($data);

        return $route;
    }

    public function delete(TransportRoute $route): void
    {
        if ($route->assignments()->exists()) {
            throw new HasDependentRecordsException(
                'Students are still assigned to this route. Move them to another route first.'
            );
        }
        if ($route->trips()->exists()) {
            throw new HasDependentRecordsException(
                'This route has trip history and cannot be deleted. Deactivate it instead.'
            );
        }

        // Stops cascade with the route.
        $route->delete();
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function addStop(TransportRoute $route, array $data): TransportStop
    {
        return $route->stops()->create([...$data, 'school_id' => $route->school_id]);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function updateStop(TransportStop $stop, array $data): TransportStop
    {
        $stop->update($data);

        return $stop;
    }

    public function deleteStop(TransportStop $stop): void
    {
        if ($stop->assignments()->exists()) {
            throw new HasDependentRecordsException(
                'Students are still assigned to this stop. Move them to another stop first.'
            );
        }

        $stop->delete();
    }
}

<?php

namespace App\Services;

use App\Enums\TransportStatus;
use App\Exceptions\HasDependentRecordsException;
use App\Models\TransportRoute;
use App\Models\TransportStop;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolScope;
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
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            // A name is unique within a school at most, and a Super Admin's
            // list spans every school - "Bus 1" is at all of them. The id
            // keeps paging from showing one twice and another never.
            ->orderBy('name')
            ->orderBy('id')
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
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

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

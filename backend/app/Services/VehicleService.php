<?php

namespace App\Services;

use App\Enums\TransportStatus;
use App\Exceptions\HasDependentRecordsException;
use App\Models\User;
use App\Models\Vehicle;
use App\Support\Pagination;
use App\Support\SchoolScope;
use Illuminate\Pagination\LengthAwarePaginator;

class VehicleService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return Vehicle::query()
            ->with(['school', 'route'])
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            ->orderBy('name')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Vehicle
    {
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

        return Vehicle::create([...$data, 'status' => TransportStatus::Active]);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Vehicle $vehicle, array $data): Vehicle
    {
        $vehicle->update($data);

        return $vehicle;
    }

    public function delete(Vehicle $vehicle): void
    {
        if ($vehicle->route()->exists()) {
            throw new HasDependentRecordsException(
                'This vehicle is still serving a route. Remove it from the route first.'
            );
        }
        if ($vehicle->trips()->exists()) {
            throw new HasDependentRecordsException(
                'This vehicle has trip history and cannot be deleted. Deactivate it instead.'
            );
        }

        $vehicle->delete();
    }
}

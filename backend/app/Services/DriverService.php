<?php

namespace App\Services;

use App\Enums\TransportStatus;
use App\Exceptions\HasDependentRecordsException;
use App\Models\Driver;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolScope;
use Illuminate\Pagination\LengthAwarePaginator;

class DriverService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return Driver::query()
            ->with(['school', 'route'])
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
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Driver
    {
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

        return Driver::create([...$data, 'status' => TransportStatus::Active]);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Driver $driver, array $data): Driver
    {
        $driver->update($data);

        return $driver;
    }

    public function delete(Driver $driver): void
    {
        if ($driver->route()->exists()) {
            throw new HasDependentRecordsException(
                'This driver is still assigned to a route. Remove them from the route first.'
            );
        }
        if ($driver->trips()->exists()) {
            throw new HasDependentRecordsException(
                'This driver has trip history and cannot be deleted. Deactivate them instead.'
            );
        }

        $driver->delete();
    }
}

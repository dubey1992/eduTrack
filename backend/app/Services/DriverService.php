<?php

namespace App\Services;

use App\Enums\TransportStatus;
use App\Enums\UserRole;
use App\Exceptions\HasDependentRecordsException;
use App\Models\Driver;
use App\Models\User;
use App\Support\Pagination;
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
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Driver
    {
        if ($actor->role !== UserRole::SuperAdmin) {
            $data['school_id'] = $actor->school_id;
        }

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

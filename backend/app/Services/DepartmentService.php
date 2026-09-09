<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Exceptions\HasDependentRecordsException;
use App\Models\Department;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;

class DepartmentService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return Department::query()
            ->with(['school', 'hod'])
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id),
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
            ->orderBy('name')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Department
    {
        if ($actor->role !== UserRole::SuperAdmin) {
            $data['school_id'] = $actor->school_id;
        }

        return Department::create($data);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Department $department, array $data): Department
    {
        $department->update($data);

        return $department;
    }

    public function delete(Department $department): void
    {
        if ($department->subjects()->exists()) {
            throw new HasDependentRecordsException(
                'This department still has subjects assigned to it. Reassign or remove them first.'
            );
        }

        $department->delete();
    }
}

<?php

namespace App\Services;

use App\Exceptions\HasDependentRecordsException;
use App\Models\Department;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolScope;
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
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            ->orderBy('name')
            // A tiebreaker. The name is unique within a school but not
            // across them, so a cross-school list ties constantly. See
            // StableOrderingTest.
            ->orderBy('id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Department
    {
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

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

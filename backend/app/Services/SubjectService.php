<?php

namespace App\Services;

use App\Models\Subject;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolScope;
use Illuminate\Pagination\LengthAwarePaginator;

class SubjectService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return Subject::query()
            ->with(['school', 'department', 'leadTeacher'])
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            ->when(
                $filters['department_id'] ?? null,
                fn ($query, $departmentId) => $query->where('department_id', $departmentId)
            )
            ->orderBy('name')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Subject
    {
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

        return Subject::create($data);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Subject $subject, array $data): Subject
    {
        $subject->update($data);

        return $subject;
    }

    public function delete(Subject $subject): void
    {
        $subject->delete();
    }
}

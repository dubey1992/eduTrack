<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Models\Subject;
use App\Models\User;
use App\Support\Pagination;
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
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id),
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
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
        if ($actor->role !== UserRole::SuperAdmin) {
            $data['school_id'] = $actor->school_id;
        }

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

<?php

namespace App\Services;

use App\Enums\StudentStatus;
use App\Enums\UserRole;
use App\Models\Student;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolScope;
use Illuminate\Pagination\LengthAwarePaginator;

class StudentService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return Student::query()
            ->with(['school', 'classSection.schoolClass', 'transportAssignment.route.vehicle', 'transportAssignment.stop'])
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            // A teacher only ever sees students in sections they are the
            // class teacher of - never another class, regardless of filters.
            ->when(
                $actor->role === UserRole::Teacher,
                fn ($query) => $query->whereHas(
                    'classSection',
                    fn ($query) => $query->where('class_teacher_id', $actor->id)
                )
            )
            ->when(
                $filters['class_section_id'] ?? null,
                fn ($query, $classSectionId) => $query->where('class_section_id', $classSectionId)
            )
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            ->when(
                $filters['search'] ?? null,
                fn ($query, $search) => $query->where(
                    fn ($query) => $query
                        ->where('first_name', 'like', "%{$search}%")
                        ->orWhere('last_name', 'like', "%{$search}%")
                        ->orWhere('admission_number', 'like', "%{$search}%")
                )
            )
            ->orderBy('first_name')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Student
    {
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

        return Student::create([...$data, 'status' => StudentStatus::Active]);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Student $student, array $data): Student
    {
        $student->update($data);

        return $student;
    }

    public function activate(Student $student): Student
    {
        $student->update(['status' => StudentStatus::Active]);

        return $student;
    }

    public function deactivate(Student $student): Student
    {
        $student->update(['status' => StudentStatus::Inactive]);

        return $student;
    }
}

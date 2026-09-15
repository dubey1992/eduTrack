<?php

namespace App\Services;

use App\Exceptions\HasDependentRecordsException;
use App\Models\ClassSection;
use App\Models\SchoolClass;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolScope;
use Illuminate\Pagination\LengthAwarePaginator;

class SchoolClassService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return SchoolClass::query()
            ->with(['school', 'academicYear', 'sections.classTeacher'])
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            ->when(
                $filters['academic_year_id'] ?? null,
                fn ($query, $academicYearId) => $query->where('academic_year_id', $academicYearId)
            )
            ->orderBy('level')
            ->orderBy('name')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): SchoolClass
    {
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

        return SchoolClass::create($data);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(SchoolClass $schoolClass, array $data): SchoolClass
    {
        $schoolClass->update($data);

        return $schoolClass;
    }

    public function delete(SchoolClass $schoolClass): void
    {
        if ($schoolClass->sections()->exists()) {
            throw new HasDependentRecordsException(
                'This class still has sections under it. Remove them first.'
            );
        }

        $schoolClass->delete();
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function addSection(SchoolClass $schoolClass, array $data): ClassSection
    {
        return $schoolClass->sections()->create($data);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function updateSection(ClassSection $section, array $data): ClassSection
    {
        $section->update($data);

        return $section;
    }

    public function deleteSection(ClassSection $section): void
    {
        if ($section->students()->exists()) {
            throw new HasDependentRecordsException(
                'This section still has students assigned to it. Reassign or remove them first.'
            );
        }

        $section->delete();
    }
}

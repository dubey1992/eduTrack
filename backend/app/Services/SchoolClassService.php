<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Exceptions\HasDependentRecordsException;
use App\Models\ClassSection;
use App\Models\SchoolClass;
use App\Models\User;
use App\Support\Pagination;
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
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id),
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
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
        if ($actor->role !== UserRole::SuperAdmin) {
            $data['school_id'] = $actor->school_id;
        }

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

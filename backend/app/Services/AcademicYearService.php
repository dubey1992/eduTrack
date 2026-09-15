<?php

namespace App\Services;

use App\Exceptions\HasDependentRecordsException;
use App\Models\AcademicYear;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolScope;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class AcademicYearService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return AcademicYear::query()
            ->with('school')
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            ->orderByDesc('start_date')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): AcademicYear
    {
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

        return DB::transaction(function () use ($data) {
            if ($data['is_current'] ?? false) {
                $this->clearCurrentFor($data['school_id']);
            }

            return AcademicYear::create($data);
        });
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(AcademicYear $academicYear, array $data): AcademicYear
    {
        $academicYear->update($data);

        return $academicYear;
    }

    public function setCurrent(AcademicYear $academicYear): AcademicYear
    {
        DB::transaction(function () use ($academicYear) {
            $this->clearCurrentFor($academicYear->school_id);
            $academicYear->update(['is_current' => true]);
        });

        return $academicYear->refresh();
    }

    public function delete(AcademicYear $academicYear): void
    {
        if ($academicYear->classes()->exists()) {
            throw new HasDependentRecordsException(
                'This academic year still has classes set up under it. Remove them first.'
            );
        }

        $academicYear->delete();
    }

    private function clearCurrentFor(int $schoolId): void
    {
        AcademicYear::query()->where('school_id', $schoolId)->update(['is_current' => false]);
    }
}

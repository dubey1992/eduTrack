<?php

namespace App\Services;

use App\Exceptions\HasDependentRecordsException;
use App\Models\Period;
use App\Models\User;
use App\Support\SchoolScope;
use Illuminate\Support\Collection;

class PeriodService
{
    /**
     * @param  array<string, mixed>  $filters
     * @return Collection<int, Period>
     */
    public function list(User $actor, array $filters): Collection
    {
        return Period::query()
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $filters['school_id'] ?? null))
            ->orderBy('period_number')
            ->get();
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Period
    {
        // Never the client's school_id: an actor pinned to one school
        // writes into it whatever the request said (CLAUDE.md rule 10).
        $data['school_id'] = SchoolScope::for($actor)->writableSchoolId($data['school_id'] ?? null);

        return Period::create($data);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Period $period, array $data): Period
    {
        $period->update($data);

        return $period;
    }

    public function delete(Period $period): void
    {
        if ($period->timetableEntries()->exists()) {
            throw new HasDependentRecordsException(
                'This period still has timetable entries scheduled against it. Remove them first.'
            );
        }

        $period->delete();
    }
}

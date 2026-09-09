<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Exceptions\HasDependentRecordsException;
use App\Models\Period;
use App\Models\User;
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
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id),
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
            ->orderBy('period_number')
            ->get();
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Period
    {
        if ($actor->role !== UserRole::SuperAdmin) {
            $data['school_id'] = $actor->school_id;
        }

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

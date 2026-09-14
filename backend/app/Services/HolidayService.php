<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Exceptions\HolidayOverlapException;
use App\Models\Attendance;
use App\Models\DailyTeachingReport;
use App\Models\Holiday;
use App\Models\StaffAttendance;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * The school holiday calendar, plus the "is this a working day?" questions
 * every date-driven module asks of it (attendance, leave, teaching reports,
 * the HOD report). A working day is a Monday-Friday date that is not
 * covered by a holiday - weekends are fixed, matching Phase 10's
 * Monday-Friday timetable.
 */
class HolidayService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return Holiday::query()
            ->with('school')
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id),
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
            ->when($filters['date_from'] ?? null, fn ($query, $date) => $query->where('end_date', '>=', $date))
            ->when($filters['date_to'] ?? null, fn ($query, $date) => $query->where('start_date', '<=', $date))
            ->orderBy('start_date')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data, User $actor): Holiday
    {
        if ($actor->role !== UserRole::SuperAdmin) {
            $data['school_id'] = $actor->school_id;
        }

        $this->assertNoOverlap($data['school_id'], $data['start_date'], $data['end_date']);

        $holiday = Holiday::create($data);

        return $this->withAffectedRecords($holiday);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(Holiday $holiday, array $data): Holiday
    {
        $start = $data['start_date'] ?? $holiday->start_date->toDateString();
        $end = $data['end_date'] ?? $holiday->end_date->toDateString();
        $this->assertNoOverlap($holiday->school_id, $start, $end, ignoreId: $holiday->id);

        $holiday->update($data);

        return $this->withAffectedRecords($holiday);
    }

    /**
     * Counts the day's records that now sit on a non-working day.
     *
     * A holiday declared after the fact is a legitimate correction - a strike
     * day, a closure nobody knew about on the morning. What is not legitimate
     * is doing it silently: those records stop counting towards every
     * working-day figure in the product, so whoever declared it is told how
     * many there are and can go and clear them.
     */
    private function withAffectedRecords(Holiday $holiday): Holiday
    {
        $between = [$holiday->start_date->toDateString(), $holiday->end_date->toDateString()];

        $holiday->setAttribute('affected_records', [
            'attendance' => Attendance::query()
                ->where('school_id', $holiday->school_id)
                ->whereBetween('attendance_date', $between)
                ->count(),
            'staff_attendance' => StaffAttendance::query()
                ->where('school_id', $holiday->school_id)
                ->whereBetween('attendance_date', $between)
                ->count(),
            'teaching_reports' => DailyTeachingReport::query()
                ->where('school_id', $holiday->school_id)
                ->whereBetween('report_date', $between)
                ->count(),
        ]);

        return $holiday;
    }

    public function delete(Holiday $holiday): void
    {
        $holiday->delete();
    }

    public function holidayOn(int $schoolId, string $date): ?Holiday
    {
        return Holiday::query()
            ->where('school_id', $schoolId)
            ->where('start_date', '<=', $date)
            ->where('end_date', '>=', $date)
            ->first();
    }

    public function isWorkingDay(int $schoolId, string $date): bool
    {
        return $this->workingDates($schoolId, Carbon::parse($date), Carbon::parse($date))->isNotEmpty();
    }

    /**
     * Every working date (Y-m-d) from $from to $to inclusive, in order.
     * Empty when $from is after $to.
     *
     * @return Collection<int, string>
     */
    public function workingDates(int $schoolId, Carbon $from, Carbon $to): Collection
    {
        $from = $from->copy()->startOfDay();
        $to = $to->copy()->startOfDay();
        if ($from->gt($to)) {
            return collect();
        }

        $holidays = Holiday::query()
            ->where('school_id', $schoolId)
            ->where('start_date', '<=', $to->toDateString())
            ->where('end_date', '>=', $from->toDateString())
            ->get();

        $dates = collect();
        for ($date = $from->copy(); $date->lte($to); $date->addDay()) {
            if ($date->isWeekend()) {
                continue;
            }
            $day = $date->toDateString();
            if ($holidays->contains(fn (Holiday $holiday) => $holiday->covers($day))) {
                continue;
            }
            $dates->push($day);
        }

        return $dates;
    }

    private function assertNoOverlap(int $schoolId, string $start, string $end, ?int $ignoreId = null): void
    {
        $overlapping = Holiday::query()
            ->where('school_id', $schoolId)
            ->where('start_date', '<=', $end)
            ->where('end_date', '>=', $start)
            ->when($ignoreId, fn ($query, $id) => $query->whereKeyNot($id))
            ->first();

        if ($overlapping !== null) {
            throw new HolidayOverlapException("These dates overlap the existing holiday \"{$overlapping->name}\".");
        }
    }
}

<?php

namespace App\Support\Reports;

use App\Services\HolidayService;
use App\Support\SchoolClock;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * The window a report covers, and the working days inside it.
 *
 * Every percentage in a report is "out of the days the school actually ran",
 * so the denominator is computed once, here, from the same holiday calendar
 * that decides whether a register may be taken at all. A report that counted
 * weekends would quietly disagree with the screen that refused to mark them.
 */
class ReportRange
{
    /** @var Collection<int, string> */
    public readonly Collection $workingDates;

    private function __construct(
        public readonly int $schoolId,
        public readonly Carbon $from,
        public readonly Carbon $to,
        Collection $workingDates,
    ) {
        $this->workingDates = $workingDates;
    }

    /**
     * Builds the range from a request's filters.
     *
     * An absent range means "this month so far" at the school - never to the
     * end of a month that has not happened, which would report a percentage
     * against days nobody has taught yet.
     *
     * @param  array<string, mixed>  $filters
     */
    public static function fromFilters(int $schoolId, array $filters, HolidayService $holidays): self
    {
        $clock = SchoolClock::for($schoolId);
        $today = $clock->today();

        $from = isset($filters['from']) ? Carbon::parse((string) $filters['from']) : $today->copy()->startOfMonth();
        $to = isset($filters['to']) ? Carbon::parse((string) $filters['to']) : $today->copy();

        $from = $from->startOfDay();
        // Never past today at the school: days that have not happened are not
        // days anyone failed to mark.
        $to = $to->startOfDay()->min($today);

        return new self($schoolId, $from, $to, $holidays->workingDates($schoolId, $from, $to));
    }

    public function workingDayCount(): int
    {
        return $this->workingDates->count();
    }

    /**
     * @return array{0: string, 1: string}
     */
    public function bounds(): array
    {
        return [$this->from->toDateString(), $this->to->toDateString()];
    }

    /**
     * A percentage of the working days in this range, to one decimal.
     *
     * Null rather than zero when the range contains no working day at all -
     * a week of holidays has no attendance rate, and printing "0%" would
     * read as everybody being absent.
     */
    public function rate(int $count): ?float
    {
        $days = $this->workingDayCount();

        return $days === 0 ? null : round($count / $days * 100, 1);
    }

    /**
     * @return array<string, mixed>
     */
    public function toArray(): array
    {
        return [
            'from' => $this->from->toDateString(),
            'to' => $this->to->toDateString(),
            'working_days' => $this->workingDayCount(),
        ];
    }
}

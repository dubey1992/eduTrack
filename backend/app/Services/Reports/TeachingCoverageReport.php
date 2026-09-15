<?php

namespace App\Services\Reports;

use App\Models\DailyTeachingReport;
use App\Models\Subject;
use App\Models\SyllabusTopic;
use App\Models\SyllabusTopicProgress;
use App\Models\TimetableEntry;
use App\Support\Reports\CombinesTotals;
use App\Support\Reports\ReportRange;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Whether teaching is happening as timetabled, per subject.
 *
 * "Scheduled" is worked out from the timetable and the calendar rather than
 * stored anywhere: a Monday period is scheduled once for every working Monday
 * in the range. That is what makes the figure honest when a holiday removes a
 * day - the periods that would have run on it are not counted as missed.
 */
class TeachingCoverageReport implements CombinesTotals
{
    /**
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    public function build(ReportRange $range, array $filters): array
    {
        $workingDaysByWeekday = $this->workingDaysByWeekday($range);
        $scheduled = $this->scheduledPerSubject($range, $filters, $workingDaysByWeekday);
        $reported = $this->reportedPerSubject($range, $filters);
        $syllabus = $this->syllabusPerSubject($range, $filters);

        $subjects = Subject::query()
            ->where('school_id', $range->schoolId)
            ->when(
                $filters['department_ids'] ?? null,
                fn (Builder $query, array $ids) => $query->whereIn('department_id', $ids)
            )
            ->with('department')
            ->orderBy('name')
            ->get();

        $rows = $subjects->map(function (Subject $subject) use ($scheduled, $reported, $syllabus) {
            $periodsScheduled = (int) ($scheduled[$subject->id] ?? 0);
            $periodsReported = (int) ($reported[$subject->id] ?? 0);
            $topics = $syllabus->get($subject->id, ['total' => 0, 'completed' => 0]);

            return [
                'subject_id' => $subject->id,
                'subject' => $subject->name,
                'department' => $subject->department?->name,
                'periods_scheduled' => $periodsScheduled,
                'periods_reported' => $periodsReported,
                // Periods on the timetable that nobody filed a report for.
                'periods_missing' => max(0, $periodsScheduled - $periodsReported),
                'coverage_rate' => $periodsScheduled === 0
                    ? null
                    : round($periodsReported / $periodsScheduled * 100, 1),
                'topics_total' => $topics['total'],
                'topics_completed' => $topics['completed'],
                'syllabus_completion' => $topics['total'] === 0
                    ? null
                    : round($topics['completed'] / $topics['total'] * 100, 1),
            ];
        });

        $totalScheduled = (int) $rows->sum('periods_scheduled');
        $totalReported = (int) $rows->sum('periods_reported');

        return [
            'range' => $range->toArray(),
            'rows' => $rows->all(),
            'totals' => [
                'subjects' => $rows->count(),
                'periods_scheduled' => $totalScheduled,
                'periods_reported' => $totalReported,
                'periods_missing' => max(0, $totalScheduled - $totalReported),
                'coverage_rate' => $totalScheduled === 0
                    ? null
                    : round($totalReported / $totalScheduled * 100, 1),
            ],
        ];
    }

    /**
     * @return array<int, string>
     */
    public function headings(): array
    {
        return ['Subject', 'Department', 'Periods scheduled', 'Reports filed', 'Missing', 'Coverage %', 'Topics', 'Topics completed', 'Syllabus %'];
    }

    /**
     * @param  array<string, mixed>  $report
     * @return array<int, array<int, mixed>>
     */
    public function csvRows(array $report): array
    {
        return array_map(fn (array $row) => [
            $row['subject'],
            $row['department'],
            $row['periods_scheduled'],
            $row['periods_reported'],
            $row['periods_missing'],
            $row['coverage_rate'],
            $row['topics_total'],
            $row['topics_completed'],
            $row['syllabus_completion'],
        ], $report['rows']);
    }

    /**
     * How many working days in the range fall on each weekday, e.g.
     * ['monday' => 3, 'tuesday' => 4]. Holidays are already excluded.
     *
     * @return array<string, int>
     */
    private function workingDaysByWeekday(ReportRange $range): array
    {
        return $range->workingDates
            ->countBy(fn (string $date) => strtolower(Carbon::parse($date)->format('l')))
            ->all();
    }

    /**
     * @param  array<string, mixed>  $filters
     * @param  array<string, int>  $workingDaysByWeekday
     * @return array<int, int>
     */
    private function scheduledPerSubject(ReportRange $range, array $filters, array $workingDaysByWeekday): array
    {
        $entries = TimetableEntry::query()
            ->where('school_id', $range->schoolId)
            ->when(
                $filters['class_section_id'] ?? null,
                fn (Builder $query, $sectionId) => $query->where('class_section_id', $sectionId)
            )
            ->selectRaw('subject_id, day_of_week, COUNT(*) as periods')
            ->groupBy('subject_id', 'day_of_week')
            ->get();

        $scheduled = [];

        foreach ($entries as $entry) {
            $weekday = $entry->day_of_week instanceof \BackedEnum
                ? $entry->day_of_week->value
                : (string) $entry->day_of_week;
            $days = $workingDaysByWeekday[$weekday] ?? 0;
            $scheduled[$entry->subject_id] = ($scheduled[$entry->subject_id] ?? 0) + ((int) $entry->periods * $days);
        }

        return $scheduled;
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return array<int, int>
     */
    private function reportedPerSubject(ReportRange $range, array $filters): array
    {
        [$from, $to] = $range->bounds();

        return DailyTeachingReport::query()
            ->where('daily_teaching_reports.school_id', $range->schoolId)
            ->join('timetable_entries', 'timetable_entries.id', '=', 'daily_teaching_reports.timetable_entry_id')
            ->whereBetween('report_date', [$from, $to])
            ->whereIn('report_date', $range->workingDates)
            ->when(
                $filters['class_section_id'] ?? null,
                fn ($query, $sectionId) => $query->where('timetable_entries.class_section_id', $sectionId)
            )
            ->selectRaw('timetable_entries.subject_id as subject_id, COUNT(*) as total')
            ->groupBy('timetable_entries.subject_id')
            ->pluck('total', 'subject_id')
            ->map(fn ($total) => (int) $total)
            ->all();
    }

    /**
     * Syllabus topics and how many have been marked complete, per subject.
     *
     * Not bounded by the range: a syllabus is cumulative progress through a
     * year, and "35% covered" means 35% of the course, not of one month.
     *
     * @param  array<string, mixed>  $filters
     * @return Collection<int, array{total: int, completed: int}>
     */
    private function syllabusPerSubject(ReportRange $range, array $filters): Collection
    {
        $totals = SyllabusTopic::query()
            ->where('school_id', $range->schoolId)
            ->selectRaw('subject_id, COUNT(*) as total')
            ->groupBy('subject_id')
            ->pluck('total', 'subject_id');

        $completed = SyllabusTopicProgress::query()
            ->where('syllabus_topic_progress.school_id', $range->schoolId)
            ->join('syllabus_topics', 'syllabus_topics.id', '=', 'syllabus_topic_progress.syllabus_topic_id')
            ->when(
                $filters['class_section_id'] ?? null,
                fn ($query, $sectionId) => $query->where('syllabus_topic_progress.class_section_id', $sectionId)
            )
            ->selectRaw('syllabus_topics.subject_id as subject_id, COUNT(DISTINCT syllabus_topics.id) as total')
            ->groupBy('syllabus_topics.subject_id')
            ->pluck('total', 'subject_id');

        return $totals->map(fn ($total, $subjectId) => [
            'total' => (int) $total,
            'completed' => (int) ($completed[$subjectId] ?? 0),
        ]);
    }

    /**
     * @param  array<int, array<string, mixed>>  $branchTotals
     * @return array<string, mixed>
     */
    public function combineTotals(array $branchTotals): array
    {
        $sum = fn (string $key) => (int) array_sum(array_column($branchTotals, $key));
        $scheduled = $sum('periods_scheduled');

        return [
            'branches' => count($branchTotals),
            'subjects' => $sum('subjects'),
            'periods_scheduled' => $scheduled,
            'periods_reported' => $sum('periods_reported'),
            'periods_missing' => $sum('periods_missing'),
            // Periods reported over periods scheduled, across the group.
            'coverage_rate' => $scheduled === 0 ? null : round($sum('periods_reported') / $scheduled * 100, 1),
        ];
    }
}

<?php

namespace App\Services\Reports;

use App\Enums\AttendanceStatus;
use App\Enums\StudentStatus;
use App\Models\Attendance;
use App\Models\Student;
use App\Support\Reports\CombinesTotals;
use App\Support\Reports\ReportRange;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;

/**
 * Attendance per student over a range: how many working days the school ran,
 * how many the student was present for, and what that is as a percentage.
 *
 * The denominator is the school's working days, not the days that happen to
 * have a register - so a class whose teacher never marked attendance reads
 * as 0%, which is the truth, rather than as having no data.
 */
class StudentAttendanceReport implements CombinesTotals
{
    /**
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    public function build(ReportRange $range, array $filters): array
    {
        $students = $this->studentsQuery($range->schoolId, $filters)
            ->with(['classSection.schoolClass'])
            ->orderBy('first_name')
            ->orderBy('last_name')
            ->orderBy('id')
            ->get();

        $marks = $this->marksByStudent($range, $students->pluck('id'));

        $rows = $students->map(function (Student $student) use ($marks, $range) {
            $counts = $marks->get($student->id, collect());
            $present = (int) $counts->get(AttendanceStatus::Present->value, 0);
            $absent = (int) $counts->get(AttendanceStatus::Absent->value, 0);
            $leave = (int) $counts->get(AttendanceStatus::Leave->value, 0);
            $section = $student->classSection;

            return [
                'student_id' => $student->id,
                'admission_number' => $student->admission_number,
                'name' => $student->name,
                'class_section' => $section === null
                    ? null
                    : trim("{$section->schoolClass?->name} {$section->name}"),
                'working_days' => $range->workingDayCount(),
                'present' => $present,
                'absent' => $absent,
                'leave' => $leave,
                // Days with no mark at all. Called out rather than folded into
                // "absent": nobody said this student was away, only that the
                // register was never taken.
                'not_marked' => max(0, $range->workingDayCount() - $present - $absent - $leave),
                'attendance_rate' => $range->rate($present),
            ];
        })->values();

        return [
            'range' => $range->toArray(),
            'rows' => $rows->all(),
            'totals' => $this->totals($rows, $range),
        ];
    }

    /**
     * @return array<int, string>
     */
    public function headings(): array
    {
        return ['Admission No.', 'Student', 'Class', 'Working days', 'Present', 'Absent', 'Leave', 'Not marked', 'Attendance %'];
    }

    /**
     * @param  array<string, mixed>  $report
     * @return array<int, array<int, mixed>>
     */
    public function csvRows(array $report): array
    {
        return array_map(fn (array $row) => [
            $row['admission_number'],
            $row['name'],
            $row['class_section'],
            $row['working_days'],
            $row['present'],
            $row['absent'],
            $row['leave'],
            $row['not_marked'],
            $row['attendance_rate'],
        ], $report['rows']);
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return Builder<Student>
     */
    private function studentsQuery(int $schoolId, array $filters): Builder
    {
        return Student::query()
            ->where('school_id', $schoolId)
            ->where('status', StudentStatus::Active)
            ->when(
                $filters['class_section_id'] ?? null,
                fn (Builder $query, $sectionId) => $query->where('class_section_id', $sectionId)
            );
    }

    /**
     * One grouped query for every student's marks, rather than a query per
     * student - a class of forty would otherwise be forty round trips.
     *
     * @param  Collection<int, int>  $studentIds
     * @return Collection<int, Collection<string, int>>
     */
    private function marksByStudent(ReportRange $range, Collection $studentIds): Collection
    {
        [$from, $to] = $range->bounds();

        return Attendance::query()
            ->where('school_id', $range->schoolId)
            ->whereIn('student_id', $studentIds)
            ->whereBetween('attendance_date', [$from, $to])
            // A day that has since become a holiday is no longer a working
            // day, so its marks must not count towards a rate measured
            // against working days.
            ->whereIn('attendance_date', $range->workingDates)
            // Aliased: the model casts `status` to an enum, and an enum cannot be
            // an array key - pluck() would fail building the map below.
            ->selectRaw('student_id, status as status_value, COUNT(*) as total')
            ->groupBy('student_id', 'status')
            ->get()
            ->groupBy('student_id')
            ->map(fn (Collection $rows) => $rows->pluck('total', 'status_value'));
    }

    /**
     * @param  Collection<int, array<string, mixed>>  $rows
     * @return array<string, mixed>
     */
    private function totals(Collection $rows, ReportRange $range): array
    {
        $present = (int) $rows->sum('present');
        $possible = $rows->count() * $range->workingDayCount();

        return [
            'students' => $rows->count(),
            'working_days' => $range->workingDayCount(),
            'present' => $present,
            'absent' => (int) $rows->sum('absent'),
            'leave' => (int) $rows->sum('leave'),
            'not_marked' => (int) $rows->sum('not_marked'),
            'attendance_rate' => $possible === 0 ? null : round($present / $possible * 100, 1),
        ];
    }

    /**
     * @param  array<int, array<string, mixed>>  $branchTotals
     * @return array<string, mixed>
     */
    public function combineTotals(array $branchTotals): array
    {
        $sum = fn (string $key) => (int) array_sum(array_column($branchTotals, $key));

        // Recomputed from raw counts, never averaged: each branch measures
        // against its own working days, so a branch of forty and a branch of
        // four hundred must not weigh the same.
        $possible = array_sum(array_map(
            fn (array $totals) => (int) $totals['students'] * (int) $totals['working_days'],
            $branchTotals,
        ));

        return [
            'branches' => count($branchTotals),
            'students' => $sum('students'),
            'present' => $sum('present'),
            'absent' => $sum('absent'),
            'leave' => $sum('leave'),
            'not_marked' => $sum('not_marked'),
            'attendance_rate' => $possible === 0 ? null : round($sum('present') / $possible * 100, 1),
        ];
    }
}

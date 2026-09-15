<?php

namespace App\Services\Reports;

use App\Enums\LeaveStatus;
use App\Enums\StaffAttendanceStatus;
use App\Models\StaffAttendance;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Support\Reports\CombinesTotals;
use App\Support\Reports\ReportRange;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Collection;

/**
 * Attendance and leave per staff member over a range.
 *
 * Leave is counted from the attendance marks rather than from the leave
 * requests, because that is what actually happened: an approved request
 * writes a Leave mark on each working day it covers, and a request that was
 * never approved wrote nothing. Approved requests are reported alongside, by
 * type, so a payroll run in Phase 19 has both.
 */
class StaffAttendanceReport implements CombinesTotals
{
    /**
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    public function build(ReportRange $range, array $filters): array
    {
        $staff = $this->staffQuery($range->schoolId, $filters)
            ->with(['user', 'department'])
            ->get()
            ->sortBy(fn (StaffProfile $profile) => $profile->user?->name ?? '')
            ->values();

        $marks = $this->marksByProfile($range, $staff->pluck('id'));
        $leaveTypes = $this->approvedLeaveByProfile($range, $staff->pluck('id'));

        $rows = $staff->map(function (StaffProfile $profile) use ($marks, $leaveTypes, $range) {
            $counts = $marks->get($profile->id, collect());
            $present = (int) $counts->get(StaffAttendanceStatus::Present->value, 0);
            $halfDay = (int) $counts->get(StaffAttendanceStatus::HalfDay->value, 0);
            $absent = (int) $counts->get(StaffAttendanceStatus::Absent->value, 0);
            $leave = (int) $counts->get(StaffAttendanceStatus::Leave->value, 0);

            return [
                'staff_profile_id' => $profile->id,
                'employee_id' => $profile->employee_id,
                'name' => $profile->user?->name,
                'department' => $profile->department?->name,
                'designation' => $profile->designation,
                'working_days' => $range->workingDayCount(),
                'present' => $present,
                'half_day' => $halfDay,
                'absent' => $absent,
                'leave' => $leave,
                'not_marked' => max(0, $range->workingDayCount() - $present - $halfDay - $absent - $leave),
                // A half day is half a day present, which is the figure
                // payroll will want rather than a count of two kinds of row.
                'attendance_rate' => $range->rate((int) round($present + $halfDay / 2)),
                'leave_by_type' => $leaveTypes->get($profile->id, collect())->all(),
            ];
        });

        return [
            'range' => $range->toArray(),
            'rows' => $rows->all(),
            'totals' => [
                'staff' => $rows->count(),
                'working_days' => $range->workingDayCount(),
                'present' => (int) $rows->sum('present'),
                'absent' => (int) $rows->sum('absent'),
                'leave' => (int) $rows->sum('leave'),
                'not_marked' => (int) $rows->sum('not_marked'),
            ],
        ];
    }

    /**
     * @return array<int, string>
     */
    public function headings(): array
    {
        return ['Employee ID', 'Name', 'Department', 'Designation', 'Working days', 'Present', 'Half days', 'Absent', 'Leave', 'Not marked', 'Attendance %'];
    }

    /**
     * @param  array<string, mixed>  $report
     * @return array<int, array<int, mixed>>
     */
    public function csvRows(array $report): array
    {
        return array_map(fn (array $row) => [
            $row['employee_id'],
            $row['name'],
            $row['department'],
            $row['designation'],
            $row['working_days'],
            $row['present'],
            $row['half_day'],
            $row['absent'],
            $row['leave'],
            $row['not_marked'],
            $row['attendance_rate'],
        ], $report['rows']);
    }

    /**
     * @param  array<string, mixed>  $filters
     * @return Builder<StaffProfile>
     */
    private function staffQuery(int $schoolId, array $filters): Builder
    {
        return StaffProfile::query()
            ->where('school_id', $schoolId)
            ->when(
                $filters['department_id'] ?? null,
                fn (Builder $query, $departmentId) => $query->where('department_id', $departmentId)
            )
            ->when(
                // A head of department sees their own departments and no
                // others, however they came to call this report.
                $filters['department_ids'] ?? null,
                fn (Builder $query, array $ids) => $query->whereIn('department_id', $ids)
            );
    }

    /**
     * @param  Collection<int, int>  $profileIds
     * @return Collection<int, Collection<string, int>>
     */
    private function marksByProfile(ReportRange $range, Collection $profileIds): Collection
    {
        [$from, $to] = $range->bounds();

        return StaffAttendance::query()
            ->where('school_id', $range->schoolId)
            ->whereIn('staff_profile_id', $profileIds)
            ->whereBetween('attendance_date', [$from, $to])
            ->whereIn('attendance_date', $range->workingDates)
            // Aliased so pluck() keys on the string, not the cast enum.
            ->selectRaw('staff_profile_id, status as status_value, COUNT(*) as total')
            ->groupBy('staff_profile_id', 'status')
            ->get()
            ->groupBy('staff_profile_id')
            ->map(fn (Collection $rows) => $rows->pluck('total', 'status_value'));
    }

    /**
     * Approved leave requests overlapping the range, counted by type.
     *
     * @param  Collection<int, int>  $profileIds
     * @return Collection<int, Collection<string, int>>
     */
    private function approvedLeaveByProfile(ReportRange $range, Collection $profileIds): Collection
    {
        [$from, $to] = $range->bounds();

        return StaffLeave::query()
            ->where('school_id', $range->schoolId)
            ->whereIn('staff_profile_id', $profileIds)
            ->where('status', LeaveStatus::Approved)
            ->where('start_date', '<=', $to)
            ->where('end_date', '>=', $from)
            ->selectRaw('staff_profile_id, leave_type as type_value, COUNT(*) as total')
            ->groupBy('staff_profile_id', 'leave_type')
            ->get()
            ->groupBy('staff_profile_id')
            ->map(fn (Collection $rows) => $rows->pluck('total', 'type_value'));
    }

    /**
     * @param  array<int, array<string, mixed>>  $branchTotals
     * @return array<string, mixed>
     */
    public function combineTotals(array $branchTotals): array
    {
        $sum = fn (string $key) => (int) array_sum(array_column($branchTotals, $key));

        return [
            'branches' => count($branchTotals),
            'staff' => $sum('staff'),
            'present' => $sum('present'),
            'absent' => $sum('absent'),
            'leave' => $sum('leave'),
            'not_marked' => $sum('not_marked'),
        ];
    }
}

<?php

namespace App\Services;

use App\Enums\LeaveStatus;
use App\Enums\LeaveType;
use App\Enums\StaffAttendanceStatus;
use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Models\DailyTeachingReport;
use App\Models\Department;
use App\Models\Period;
use App\Models\School;
use App\Models\StaffAttendance;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\SyllabusTopic;
use App\Models\SyllabusTopicProgress;
use App\Models\TimetableEntry;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;

/**
 * Phase 13 - the "HOD / Staff Reports" page: one month of a department's
 * teaching performance, computed on the fly from what earlier phases
 * already record (nothing is stored). Definitions, fixed on 2026-09-09:
 *
 * - Working days: Monday-Friday dates in the month that are not on the
 *   school's holiday calendar (see HolidayService); for the current month,
 *   only up to today.
 * - Attendance %: (present + 0.5 x half_day) / working days.
 * - Leave days: approved leave counted on working days only, clipped to
 *   the month; half_day type = 0.5 per day.
 * - Late marks: check-ins later than the school's earliest period start.
 * - Classes assigned: timetable slots falling on working days; classes
 *   taught: the subset on days the teacher was present/half-day.
 * - Reports: daily teaching reports filed in the month (+ how many still
 *   await HOD review).
 * - Syllabus %: completed / total topics across every subject+section pair
 *   the teacher is scheduled for (cumulative, not month-bound).
 * - Status: "review" when reports await review or fewer reports were filed
 *   than classes taught; otherwise "on_track".
 */
class HodReportService
{
    private const array TEACHING_ROLES = [UserRole::Teacher, UserRole::Hod];

    public function __construct(private readonly HolidayService $holidayService) {}

    /**
     * @param  array<string, mixed>  $filters
     * @return array<string, mixed>
     */
    public function departmentReport(User $actor, School $school, ?Department $department, string $month, array $filters): array
    {
        $departments = $this->departmentsInScope($actor, $school, $department);
        $departmentIds = $departments->pluck('id')->all();

        $monthStart = Carbon::createFromFormat('Y-m', $month)->startOfMonth();
        $monthEnd = $monthStart->copy()->endOfMonth()->startOfDay();
        $range = [$monthStart->toDateString(), $monthEnd->toDateString()];

        $workingDates = $this->holidayService->workingDates($school->id, $monthStart, $monthEnd->min(now()->startOfDay()));
        $lateAfter = Period::query()->where('school_id', $school->id)->min('start_time');

        $teachersQuery = $this->teachersQuery($school, $departmentIds);
        $scopedProfileIds = (clone $teachersQuery)->pluck('staff_profiles.id');
        $leavesByProfile = $this->approvedLeaves($scopedProfileIds, $range)->groupBy('staff_profile_id');

        $page = (clone $teachersQuery)
            ->with(['user', 'department'])
            ->orderBy(User::query()->select('first_name')->whereColumn('users.id', 'staff_profiles.user_id'))
            ->orderBy('staff_profiles.id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));

        $profiles = $page->getCollection();
        $attendanceByProfile = StaffAttendance::query()
            ->whereIn('staff_profile_id', $profiles->pluck('id'))
            ->whereBetween('attendance_date', $range)
            ->get()
            ->groupBy('staff_profile_id');
        $entriesByTeacher = TimetableEntry::query()
            ->where('school_id', $school->id)
            ->whereIn('teacher_id', $profiles->pluck('user_id'))
            ->get(['teacher_id', 'day_of_week', 'subject_id', 'class_section_id'])
            ->groupBy('teacher_id');
        $reportsByTeacher = DailyTeachingReport::query()
            ->whereIn('teacher_id', $profiles->pluck('user_id'))
            ->whereBetween('report_date', $range)
            ->selectRaw('teacher_id, COUNT(*) as submitted, SUM(CASE WHEN reviewed_by IS NULL THEN 1 ELSE 0 END) as pending')
            ->groupBy('teacher_id')
            ->get()
            ->keyBy('teacher_id');
        $syllabus = $this->syllabusCoverage($entriesByTeacher->flatten(1));

        $rows = $profiles->map(fn (StaffProfile $profile) => $this->teacherRow(
            $profile,
            $workingDates,
            $lateAfter,
            $attendanceByProfile->get($profile->id, collect()),
            $leavesByProfile->get($profile->id, collect()),
            $entriesByTeacher->get($profile->user_id, collect()),
            $reportsByTeacher->get($profile->user_id),
            $syllabus,
        ))->values()->all();

        $workingDays = $workingDates->count();
        $teacherCount = $scopedProfileIds->count();
        $attendanceCredit = $this->attendanceCredit($scopedProfileIds, $range);

        return [
            'month' => $month,
            'school_id' => $school->id,
            'departments' => $departments->map(fn (Department $d) => ['id' => $d->id, 'name' => $d->name])->values()->all(),
            'working_days' => $workingDays,
            'teacher_count' => $teacherCount,
            'avg_attendance_percent' => $workingDays === 0 || $teacherCount === 0
                ? 0.0
                : round($attendanceCredit / ($workingDays * $teacherCount) * 100, 1),
            'leave_days' => $leavesByProfile->flatten(1)->sum(fn (StaffLeave $leave) => $this->leaveDaysWithin($leave, $workingDates)),
            'late_marks' => $this->lateMarks($scopedProfileIds, $range, $lateAfter),
            'data' => $rows,
            'meta' => [
                'current_page' => $page->currentPage(),
                'last_page' => $page->lastPage(),
                'total' => $page->total(),
                'per_page' => $page->perPage(),
            ],
        ];
    }

    /**
     * @param  Collection<int, string>  $workingDates
     * @param  Collection<int, StaffAttendance>  $attendance
     * @param  Collection<int, StaffLeave>  $leaves
     * @param  Collection<int, TimetableEntry>  $entries
     * @param  array{totals: Collection<int, int>, completed: Collection<string, int>}  $syllabus
     * @return array<string, mixed>
     */
    private function teacherRow(
        StaffProfile $profile,
        Collection $workingDates,
        ?string $lateAfter,
        Collection $attendance,
        Collection $leaves,
        Collection $entries,
        ?DailyTeachingReport $reports,
        array $syllabus,
    ): array {
        $statusByDate = $attendance->mapWithKeys(fn (StaffAttendance $row) => [$row->attendance_date->toDateString() => $row->status]);
        $present = $attendance->where('status', StaffAttendanceStatus::Present)->count();
        $halfDay = $attendance->where('status', StaffAttendanceStatus::HalfDay)->count();
        $workingDays = $workingDates->count();

        $slotsByDay = $entries->countBy(fn (TimetableEntry $entry) => $entry->day_of_week->value);
        $assigned = 0;
        $taught = 0;
        foreach ($workingDates as $date) {
            $slots = $slotsByDay->get(strtolower(Carbon::parse($date)->format('l')), 0);
            $assigned += $slots;
            if (in_array($statusByDate->get($date), [StaffAttendanceStatus::Present, StaffAttendanceStatus::HalfDay], true)) {
                $taught += $slots;
            }
        }

        $submitted = (int) ($reports?->submitted ?? 0);
        $pending = (int) ($reports?->pending ?? 0);

        $topicsTotal = 0;
        $topicsCompleted = 0;
        foreach ($entries->unique(fn (TimetableEntry $e) => "{$e->subject_id}-{$e->class_section_id}") as $entry) {
            $topicsTotal += $syllabus['totals']->get($entry->subject_id, 0);
            $topicsCompleted += $syllabus['completed']->get("{$entry->subject_id}-{$entry->class_section_id}", 0);
        }

        return [
            'staff_profile_id' => $profile->id,
            'user_id' => $profile->user_id,
            'teacher_name' => $profile->user->name,
            'employee_id' => $profile->employee_id,
            'department_id' => $profile->department_id,
            'department_name' => $profile->department?->name,
            'attendance_percent' => $workingDays === 0 ? 0.0 : round(($present + 0.5 * $halfDay) / $workingDays * 100, 1),
            'leave_days' => $leaves->sum(fn (StaffLeave $leave) => $this->leaveDaysWithin($leave, $workingDates)),
            'late_marks' => $lateAfter === null
                ? 0
                : $attendance->filter(fn (StaffAttendance $row) => $row->check_in !== null && strcmp($row->check_in, $lateAfter) > 0)->count(),
            'classes_assigned' => $assigned,
            'classes_taught' => $taught,
            'reports_submitted' => $submitted,
            'reports_pending_review' => $pending,
            'syllabus_percent' => $topicsTotal === 0 ? 0 : (int) round($topicsCompleted / $topicsTotal * 100),
            'status' => ($pending > 0 || $submitted < $taught) ? 'review' : 'on_track',
        ];
    }

    /**
     * @return Collection<int, Department>
     */
    private function departmentsInScope(User $actor, School $school, ?Department $department): Collection
    {
        if ($department !== null) {
            return collect([$department]);
        }

        return Department::query()
            ->where('school_id', $school->id)
            ->when($actor->role === UserRole::Hod, fn ($query) => $query->where('hod_user_id', $actor->id))
            ->orderBy('name')
            ->get();
    }

    /**
     * @param  array<int>  $departmentIds
     * @return Builder<StaffProfile>
     */
    private function teachersQuery(School $school, array $departmentIds): Builder
    {
        return StaffProfile::query()
            ->where('staff_profiles.school_id', $school->id)
            ->whereIn('staff_profiles.department_id', $departmentIds)
            ->whereHas('user', fn ($query) => $query
                ->whereIn('role', array_map(fn (UserRole $role) => $role->value, self::TEACHING_ROLES))
                ->where('status', UserStatus::Active));
    }

    /**
     * @param  Collection<int, int>  $profileIds
     * @param  array{0: string, 1: string}  $range
     * @return Collection<int, StaffLeave>
     */
    private function approvedLeaves(Collection $profileIds, array $range): Collection
    {
        return StaffLeave::query()
            ->whereIn('staff_profile_id', $profileIds)
            ->where('status', LeaveStatus::Approved)
            ->where('start_date', '<=', $range[1])
            ->where('end_date', '>=', $range[0])
            ->get();
    }

    /**
     * @param  Collection<int, string>  $workingDates
     */
    private function leaveDaysWithin(StaffLeave $leave, Collection $workingDates): float
    {
        $start = $leave->start_date->toDateString();
        $end = $leave->end_date->toDateString();
        $days = $workingDates->filter(fn (string $date) => $date >= $start && $date <= $end)->count();

        return $leave->leave_type === LeaveType::HalfDay ? $days * 0.5 : (float) $days;
    }

    /**
     * Sum of "day credits" (present = 1, half_day = 0.5) across the whole
     * scope - the numerator of the department-wide attendance average.
     *
     * @param  Collection<int, int>  $profileIds
     * @param  array{0: string, 1: string}  $range
     */
    private function attendanceCredit(Collection $profileIds, array $range): float
    {
        $counts = StaffAttendance::query()
            ->whereIn('staff_profile_id', $profileIds)
            ->whereBetween('attendance_date', $range)
            ->whereIn('status', [StaffAttendanceStatus::Present->value, StaffAttendanceStatus::HalfDay->value])
            ->selectRaw('status, COUNT(*) as total')
            ->groupBy('status')
            ->get();

        $present = (int) $counts->firstWhere('status', StaffAttendanceStatus::Present)?->total;
        $halfDay = (int) $counts->firstWhere('status', StaffAttendanceStatus::HalfDay)?->total;

        return $present + 0.5 * $halfDay;
    }

    /**
     * @param  Collection<int, int>  $profileIds
     * @param  array{0: string, 1: string}  $range
     */
    private function lateMarks(Collection $profileIds, array $range, ?string $lateAfter): int
    {
        if ($lateAfter === null) {
            return 0;
        }

        return StaffAttendance::query()
            ->whereIn('staff_profile_id', $profileIds)
            ->whereBetween('attendance_date', $range)
            ->whereNotNull('check_in')
            ->where('check_in', '>', $lateAfter)
            ->count();
    }

    /**
     * Topic totals per subject and completed counts per subject+section
     * pair, for every pair the page's teachers are scheduled for.
     *
     * @param  Collection<int, TimetableEntry>  $entries
     * @return array{totals: Collection<int, int>, completed: Collection<string, int>}
     */
    private function syllabusCoverage(Collection $entries): array
    {
        $subjectIds = $entries->pluck('subject_id')->unique()->values();
        $sectionIds = $entries->pluck('class_section_id')->unique()->values();

        if ($subjectIds->isEmpty()) {
            return ['totals' => collect(), 'completed' => collect()];
        }

        $totals = SyllabusTopic::query()
            ->whereIn('subject_id', $subjectIds)
            ->selectRaw('subject_id, COUNT(*) as total')
            ->groupBy('subject_id')
            ->pluck('total', 'subject_id')
            ->map(fn ($total) => (int) $total);

        $completed = SyllabusTopicProgress::query()
            ->join('syllabus_topics', 'syllabus_topics.id', '=', 'syllabus_topic_progress.syllabus_topic_id')
            ->whereIn('syllabus_topics.subject_id', $subjectIds)
            ->whereIn('syllabus_topic_progress.class_section_id', $sectionIds)
            ->selectRaw('syllabus_topics.subject_id, syllabus_topic_progress.class_section_id, COUNT(*) as completed')
            ->groupBy('syllabus_topics.subject_id', 'syllabus_topic_progress.class_section_id')
            ->get()
            ->mapWithKeys(fn ($row) => ["{$row->subject_id}-{$row->class_section_id}" => (int) $row->completed]);

        return ['totals' => $totals, 'completed' => $completed];
    }
}

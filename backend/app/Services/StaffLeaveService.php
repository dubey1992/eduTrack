<?php

namespace App\Services;

use App\Enums\LeaveStatus;
use App\Enums\MessageEvent;
use App\Enums\StaffAttendanceStatus;
use App\Enums\UserRole;
use App\Exceptions\LeaveAlreadyReviewedException;
use App\Exceptions\LeaveOnNonWorkingDaysException;
use App\Exceptions\LeaveOverlapException;
use App\Models\StaffAttendance;
use App\Models\StaffLeave;
use App\Models\StaffProfile;
use App\Models\User;
use App\Support\DateFormats;
use App\Support\Pagination;
use App\Support\SchoolClock;
use App\Support\SchoolScope;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

class StaffLeaveService
{
    private const array RELATIONS = ['staffProfile.user', 'staffProfile.department', 'appliedBy', 'reviewedBy'];

    public function __construct(
        private readonly HolidayService $holidayService,
        private readonly NotificationService $notifications,
    ) {}

    /**
     * A staff member applying for their own leave - staff_profile_id always
     * comes from the authenticated actor's own profile (resolved by the
     * controller), never from client input, the same "identity is derived
     * from the actor" rule CLAUDE.md rule 10 applies to school context.
     *
     * A (non-sub) School Admin is the head of their school - nobody else
     * has standing to review their leave (a Sub Admin still can't manage
     * an admin account per UserPolicy, and a peer School Admin reviewing
     * the actual head would be backwards), so their own request is
     * auto-approved on application instead of sitting pending forever. A
     * Sub Admin is still subordinate to the School Admin(s) who created
     * them and goes through the normal review flow, same as everyone else.
     *
     * @param  array<string, mixed>  $data
     */
    public function apply(StaffProfile $staffProfile, array $data, User $actor): StaffLeave
    {
        $this->assertCoversAWorkingDay($staffProfile->school_id, $data['start_date'], $data['end_date']);
        $this->assertNoOverlap($staffProfile->id, $data['start_date'], $data['end_date']);

        $isSchoolHead = $actor->role === UserRole::SchoolAdmin && ! $actor->is_sub_admin;

        return DB::transaction(function () use ($staffProfile, $data, $actor, $isSchoolHead) {
            $leave = StaffLeave::create([
                'school_id' => $staffProfile->school_id,
                'staff_profile_id' => $staffProfile->id,
                'leave_type' => $data['leave_type'],
                'start_date' => $data['start_date'],
                'end_date' => $data['end_date'],
                'reason' => $data['reason'],
                'status' => $isSchoolHead ? LeaveStatus::Approved : LeaveStatus::Pending,
                'applied_by' => $actor->id,
                'reviewed_by' => $isSchoolHead ? $actor->id : null,
                'review_remarks' => $isSchoolHead ? 'Auto-approved - School Admin is the head of the school.' : null,
            ]);

            if ($isSchoolHead) {
                $this->syncAttendance($leave, $actor);
            }

            return $leave->fresh(self::RELATIONS);
        });
    }

    /**
     * Approving a leave request also marks every date in its range as
     * "Leave" on the staff member's attendance (Phase 8) - the point of
     * this integration: an approved leave and the attendance register can
     * never silently disagree about whether the staff member was expected
     * in that day.
     */
    public function approve(StaffLeave $leave, User $actor, ?string $remarks): StaffLeave
    {
        $this->assertPending($leave);

        return DB::transaction(function () use ($leave, $actor, $remarks) {
            $leave->update([
                'status' => LeaveStatus::Approved,
                'reviewed_by' => $actor->id,
                'review_remarks' => $remarks,
            ]);

            $this->syncAttendance($leave, $actor);
            $this->notifyApplicant($leave, MessageEvent::LeaveApproved, $actor);

            return $leave->fresh(self::RELATIONS);
        });
    }

    public function reject(StaffLeave $leave, User $actor, ?string $remarks): StaffLeave
    {
        $this->assertPending($leave);

        $leave->update([
            'status' => LeaveStatus::Rejected,
            'reviewed_by' => $actor->id,
            'review_remarks' => $remarks,
        ]);

        $this->notifyApplicant($leave, MessageEvent::LeaveRejected, $actor);

        return $leave->fresh(self::RELATIONS);
    }

    /**
     * Tells the staff member what was decided, in their inbox and by SMS.
     * The reviewer's own action is never held up by the send.
     */
    private function notifyApplicant(StaffLeave $leave, MessageEvent $event, User $actor): void
    {
        $applicant = $leave->staffProfile?->user;

        if ($applicant === null) {
            return;
        }

        $this->notifications->notifyUser($event, $applicant, [
            'leave_type' => $leave->leave_type->label(),
            'start_date' => $leave->start_date->format(DateFormats::DATE),
            'end_date' => $leave->end_date->format(DateFormats::DATE),
            'days' => (string) ((int) $leave->start_date->diffInDays($leave->end_date) + 1),
            'remarks' => $leave->review_remarks,
        ], $actor);
    }

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return $this->scopedQuery($actor, $filters['school_id'] ?? null)
            ->with(self::RELATIONS)
            ->when(
                $filters['staff_profile_id'] ?? null,
                fn ($query, $staffProfileId) => $query->where('staff_profile_id', $staffProfileId)
            )
            ->when(
                $filters['department_id'] ?? null,
                fn ($query, $departmentId) => $query->whereHas(
                    'staffProfile',
                    fn ($query) => $query->where('department_id', $departmentId)
                )
            )
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            // Newest first, and id to break the tie: two requests applied for
            // in the same second are otherwise in no fixed order, which shows
            // one row twice and skips another as the reviewer pages through.
            ->orderByDesc('created_at')
            ->orderByDesc('id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * The stat cards the prototype's Staff Leave Management screen shows -
     * counted over the same role-scoped visibility as paginate(), not just
     * the current page.
     *
     * @param  array<string, mixed>  $filters
     * @return array<string, int>
     */
    public function summary(User $actor, array $filters): array
    {
        $base = $this->scopedQuery($actor, $filters['school_id'] ?? null);
        // start_date and end_date are calendar dates at the school, so "today"
        // and "this month" have to be read on the school's calendar too.
        $clock = SchoolClock::forScope($actor, $filters['school_id'] ?? null);
        $today = $clock->date();
        $monthStart = $clock->now()->startOfMonth()->toDateString();

        return [
            'pending' => (clone $base)->where('status', LeaveStatus::Pending)->count(),
            'approved_this_month' => (clone $base)
                ->where('status', LeaveStatus::Approved)
                ->where('start_date', '>=', $monthStart)
                ->count(),
            'rejected' => (clone $base)->where('status', LeaveStatus::Rejected)->count(),
            'on_leave_today' => (clone $base)
                ->where('status', LeaveStatus::Approved)
                ->where('start_date', '<=', $today)
                ->where('end_date', '>=', $today)
                ->count(),
        ];
    }

    /**
     * @return Builder<StaffLeave>
     */
    private function scopedQuery(User $actor, ?int $schoolIdFilter): Builder
    {
        return StaffLeave::query()
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, $schoolIdFilter))
            // An HOD only ever sees leave for staff in the department(s)
            // they head - same rule as StaffAttendanceService.
            ->when(
                $actor->role === UserRole::Hod,
                fn ($query) => $query->whereHas(
                    'staffProfile.department',
                    fn ($query) => $query->where('hod_user_id', $actor->id)
                )
            )
            // A Teacher/Staff/Transport Manager only ever sees their own
            // leave history - they aren't reviewers, this is self-service.
            ->when(
                in_array($actor->role, [UserRole::Teacher, UserRole::Staff, UserRole::TransportManager], true),
                fn ($query) => $query->where('staff_profile_id', $actor->staffProfile?->id ?? 0)
            );
    }

    private function assertNoOverlap(int $staffProfileId, string $start, string $end): void
    {
        $overlaps = StaffLeave::query()
            ->where('staff_profile_id', $staffProfileId)
            ->whereIn('status', [LeaveStatus::Pending, LeaveStatus::Approved])
            ->where('start_date', '<=', $end)
            ->where('end_date', '>=', $start)
            ->exists();

        if ($overlaps) {
            throw new LeaveOverlapException('This staff member already has a leave request overlapping these dates.');
        }
    }

    private function assertPending(StaffLeave $leave): void
    {
        if ($leave->status !== LeaveStatus::Pending) {
            throw new LeaveAlreadyReviewedException('This leave request has already been reviewed.');
        }
    }

    private function assertCoversAWorkingDay(int $schoolId, string $start, string $end): void
    {
        $workingDays = $this->holidayService->workingDates($schoolId, Carbon::parse($start), Carbon::parse($end));

        if ($workingDays->isEmpty()) {
            throw new LeaveOnNonWorkingDaysException(
                'The selected dates fall entirely on weekends or holidays - there is no working day to take leave from.'
            );
        }
    }

    /**
     * Only working days get a "Leave" mark - weekends and holidays inside
     * the range are not attendance days, so marking them would contradict
     * the holiday calendar (attendance can't be marked on a holiday).
     */
    private function syncAttendance(StaffLeave $leave, User $actor): void
    {
        $workingDays = $this->holidayService->workingDates($leave->school_id, $leave->start_date, $leave->end_date);

        foreach ($workingDays as $date) {
            StaffAttendance::updateOrCreate(
                ['staff_profile_id' => $leave->staff_profile_id, 'attendance_date' => $date],
                ['school_id' => $leave->school_id, 'status' => StaffAttendanceStatus::Leave, 'marked_by' => $actor->id]
            );
        }
    }
}

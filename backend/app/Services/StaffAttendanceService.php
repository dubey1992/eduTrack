<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Exceptions\AttendanceAlreadySubmittedException;
use App\Exceptions\AttendanceOnHolidayException;
use App\Models\School;
use App\Models\StaffAttendance;
use App\Models\StaffProfile;
use App\Models\User;
use App\Support\Pagination;
use App\Support\WorkingHours;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class StaffAttendanceService
{
    public function __construct(private readonly HolidayService $holidayService) {}

    /**
     * The school's (optionally department-filtered) staff roster for one
     * day, each paired with their existing mark (or null if not yet
     * submitted). An HOD's roster is always narrowed to the department(s)
     * they head, regardless of what department_id was requested - never
     * trusted from the client, same principle as AttendanceService's
     * Teacher scoping.
     *
     * @return array<string, mixed>
     */
    public function register(School $school, ?int $departmentId, string $date, User $actor): array
    {
        $staff = $this->rosterQuery($school, $departmentId, $actor)->get();

        $existing = StaffAttendance::query()
            ->where('school_id', $school->id)
            ->where('attendance_date', $date)
            ->whereIn('staff_profile_id', $staff->pluck('id'))
            ->get()
            ->keyBy('staff_profile_id');

        $holiday = $this->holidayService->holidayOn($school->id, $date);

        return [
            'school_id' => $school->id,
            'attendance_date' => $date,
            'submitted' => $existing->isNotEmpty(),
            'holiday' => $holiday === null ? null : AttendanceService::holidayPayload($holiday),
            'staff' => $staff->map(function (StaffProfile $profile) use ($existing) {
                $mark = $existing->get($profile->id);

                return [
                    'staff_profile_id' => $profile->id,
                    'employee_id' => $profile->employee_id,
                    'name' => $profile->user->name,
                    'department_name' => $profile->department?->name,
                    'status' => $mark?->status->value,
                    'check_in' => $this->formatTime($mark?->check_in),
                    'check_out' => $this->formatTime($mark?->check_out),
                    'working_hours' => WorkingHours::format($this->formatTime($mark?->check_in), $this->formatTime($mark?->check_out)),
                    'remarks' => $mark?->remarks,
                ];
            })->values()->all(),
        ];
    }

    /**
     * First submission for a school+day - rejected if any of the given
     * staff already has a mark for that day, so a duplicate tap can't
     * silently overwrite a different set of marks.
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    public function submit(School $school, array $data, User $actor): array
    {
        $alreadySubmitted = StaffAttendance::query()
            ->where('school_id', $school->id)
            ->where('attendance_date', $data['attendance_date'])
            ->whereIn('staff_profile_id', array_column($data['records'], 'staff_profile_id'))
            ->exists();

        if ($alreadySubmitted) {
            throw new AttendanceAlreadySubmittedException('Attendance has already been submitted.');
        }

        return $this->save($school, $data, $actor);
    }

    /**
     * Corrects an already-submitted day (or fills in staff the first
     * submission missed) - an explicit, separate action from submit().
     *
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    public function update(School $school, array $data, User $actor): array
    {
        return $this->save($school, $data, $actor);
    }

    /**
     * @param  array<string, mixed>  $data
     * @return array<string, mixed>
     */
    private function save(School $school, array $data, User $actor): array
    {
        $holiday = $this->holidayService->holidayOn($school->id, $data['attendance_date']);
        if ($holiday !== null) {
            throw new AttendanceOnHolidayException("Attendance cannot be marked on {$holiday->name} - it is a holiday.");
        }

        return DB::transaction(function () use ($school, $data, $actor) {
            foreach ($data['records'] as $record) {
                StaffAttendance::updateOrCreate(
                    [
                        'staff_profile_id' => $record['staff_profile_id'],
                        'attendance_date' => $data['attendance_date'],
                    ],
                    [
                        'school_id' => $school->id,
                        'status' => $record['status'],
                        'check_in' => $record['check_in'] ?? null,
                        'check_out' => $record['check_out'] ?? null,
                        'remarks' => $record['remarks'] ?? null,
                        'marked_by' => $actor->id,
                    ]
                );
            }

            return $this->register($school, $data['department_id'] ?? null, $data['attendance_date'], $actor);
        });
    }

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return StaffAttendance::query()
            ->with(['staffProfile.user', 'staffProfile.department', 'markedBy'])
            ->when(
                $actor->role === UserRole::SuperAdmin,
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                ),
                fn ($query) => $query->where('school_id', $actor->school_id)
            )
            // An HOD only ever sees attendance for staff in the
            // department(s) they head - never another department,
            // regardless of filters (same rule as the register roster).
            ->when(
                $actor->role === UserRole::Hod,
                fn ($query) => $query->whereHas(
                    'staffProfile.department',
                    fn ($query) => $query->where('hod_user_id', $actor->id)
                )
            )
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
            ->when(
                $filters['date_from'] ?? null,
                fn ($query, $date) => $query->where('attendance_date', '>=', $date)
            )
            ->when(
                $filters['date_to'] ?? null,
                fn ($query, $date) => $query->where('attendance_date', '<=', $date)
            )
            ->orderByDesc('attendance_date')
            ->orderBy('staff_profile_id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @return Builder<StaffProfile>
     */
    private function rosterQuery(School $school, ?int $departmentId, User $actor)
    {
        $query = StaffProfile::query()
            ->where('school_id', $school->id)
            ->whereHas('user', fn ($query) => $query->where('status', UserStatus::Active))
            ->with(['user', 'department'])
            ->orderBy('employee_id');

        if ($actor->role === UserRole::Hod) {
            return $query->whereHas('department', fn ($query) => $query->where('hod_user_id', $actor->id));
        }

        return $query->when($departmentId, fn ($query, $id) => $query->where('department_id', $id));
    }

    private function formatTime(?string $time): ?string
    {
        return $time === null ? null : substr($time, 0, 5);
    }
}

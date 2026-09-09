<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Models\StaffProfile;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;
use Illuminate\Support\Facades\DB;

class StaffProfileService
{
    public function __construct(private readonly UserService $userService) {}

    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return StaffProfile::query()
            ->with(['user.classTeacherOf.schoolClass', 'school', 'department'])
            ->when(
                $actor->role !== UserRole::SuperAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id),
                fn ($query) => $query->when(
                    $filters['school_id'] ?? null,
                    fn ($query, $schoolId) => $query->where('school_id', $schoolId)
                )
            )
            ->when(
                $filters['department_id'] ?? null,
                fn ($query, $departmentId) => $query->where('department_id', $departmentId)
            )
            ->whereHas('user', function ($query) use ($filters) {
                $query
                    ->when($filters['role'] ?? null, fn ($query, $role) => $query->where('role', $role))
                    ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
                    ->when(
                        $filters['search'] ?? null,
                        fn ($query, $search) => $query->where(
                            fn ($query) => $query
                                ->where('first_name', 'like', "%{$search}%")
                                ->orWhere('last_name', 'like', "%{$search}%")
                                ->orWhere('email', 'like', "%{$search}%")
                        )
                    );
            })
            ->orderBy('employee_id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * Creates the login account and the employment profile together in one
     * transaction, matching the prototype's single "Add Employee" form.
     *
     * @param  array<string, mixed>  $userData
     * @param  array<string, mixed>  $profileData
     */
    public function createEmployee(array $userData, array $profileData, User $actor): StaffProfile
    {
        return DB::transaction(function () use ($userData, $profileData, $actor) {
            $user = $this->userService->create($actor, $userData);

            $staffProfile = StaffProfile::create([
                ...$profileData,
                'user_id' => $user->id,
                // Always the account's own school - resolved by UserService::create
                // above, never re-derived from client input here.
                'school_id' => $user->school_id,
            ]);

            return $staffProfile->load(['user.classTeacherOf.schoolClass', 'school', 'department']);
        });
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(StaffProfile $staffProfile, array $data): StaffProfile
    {
        $staffProfile->update($data);

        return $staffProfile;
    }
}

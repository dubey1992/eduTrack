<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Enums\UserStatus;
use App\Models\StaffProfile;
use App\Models\User;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;

class UserService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters): LengthAwarePaginator
    {
        return User::query()
            ->with('school')
            // SCHOOL_ADMIN only ever sees their own school - never trust a
            // client-supplied school filter for this (CLAUDE.md rule 12).
            ->when(
                $actor->role === UserRole::SchoolAdmin,
                fn ($query) => $query->where('school_id', $actor->school_id)
            )
            ->when($filters['role'] ?? null, fn ($query, $role) => $query->where('role', $role))
            // Comma-separated shorthand for "any of these roles" - used by
            // the academic-config pickers (HOD/lead-teacher/class-teacher).
            ->when(
                $filters['roles'] ?? null,
                fn ($query, $roles) => $query->whereIn('role', explode(',', $roles))
            )
            ->when($filters['status'] ?? null, fn ($query, $status) => $query->where('status', $status))
            // Only meaningful for a SUPER_ADMIN actor - a SCHOOL_ADMIN is
            // already forced into their own school above.
            ->when($filters['school_id'] ?? null, fn ($query, $schoolId) => $query->where('school_id', $schoolId))
            ->orderBy('first_name')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(User $actor, array $data): User
    {
        // A non-SUPER_ADMIN actor's creations always land in their own
        // school - used both here (a School Admin creating a Sub Admin)
        // and by StaffProfileService::createEmployee() (Teachers & Staff) -
        // never trusted from client input either way.
        if ($actor->role !== UserRole::SuperAdmin) {
            $data['school_id'] = $actor->school_id;
        }

        // Only meaningful when creating a SCHOOL_ADMIN (StoreUserRequest's
        // only allowed role): a School Admin created by SUPER_ADMIN can
        // create further admin accounts; one created by another School
        // Admin - a "Sub Admin" - has the same permissions everywhere else
        // but cannot (see UserPolicy::create()).
        if (($data['role'] ?? null) === UserRole::SchoolAdmin->value) {
            $data['is_sub_admin'] = $actor->role !== UserRole::SuperAdmin;
        }

        $user = User::create([
            ...$data,
            'status' => UserStatus::Active,
        ]);

        // A School/Sub Admin otherwise has no StaffProfile at all, which
        // blocks them from self-service actions that key off one (Staff
        // Leave, Staff Attendance). A minimal profile - no department, a
        // placeholder employee id - is enough for those; it deliberately
        // doesn't appear in the Teachers & Staff roster (see
        // StaffProfileService::paginate()), since it isn't a real
        // employment record the way Teachers & Staff onboarding produces one.
        if ($user->role === UserRole::SchoolAdmin) {
            StaffProfile::create([
                'user_id' => $user->id,
                'school_id' => $user->school_id,
                'employee_id' => 'ADMIN-'.$user->id,
                'department_id' => null,
                'designation' => $user->is_sub_admin ? 'Sub Admin' : 'School Admin',
                'joining_date' => now()->toDateString(),
            ]);
        }

        return $user;
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(User $user, array $data): User
    {
        $user->update($data);

        return $user;
    }

    public function activate(User $user): User
    {
        $user->update(['status' => UserStatus::Active]);

        return $user;
    }

    public function deactivate(User $user): User
    {
        $user->update(['status' => UserStatus::Inactive]);
        $user->tokens()->delete();

        return $user;
    }
}

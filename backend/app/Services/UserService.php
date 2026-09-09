<?php

namespace App\Services;

use App\Enums\UserRole;
use App\Enums\UserStatus;
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
        if ($actor->role === UserRole::SchoolAdmin) {
            $data['school_id'] = $actor->school_id;
        }

        return User::create([
            ...$data,
            'status' => UserStatus::Active,
        ]);
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

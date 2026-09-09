<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\StaffProfile;
use App\Models\User;

/**
 * Same shape as UserPolicy - SUPER_ADMIN manages every school's staff,
 * SCHOOL_ADMIN manages their own school's staff only. School scoping is
 * always read from the actor's own `school_id`, never from client input.
 * See CLAUDE.md rules 12 and 15.
 */
class StaffProfilePolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function view(User $actor, StaffProfile $staffProfile): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin && $actor->school_id === $staffProfile->school_id;
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, StaffProfile $staffProfile): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin && $actor->school_id === $staffProfile->school_id;
    }
}

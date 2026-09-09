<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Holiday;
use App\Models\User;

/**
 * Same shape as DepartmentPolicy - SUPER_ADMIN full access, SCHOOL_ADMIN
 * scoped to their own school, every other role read-only (everyone needs
 * to see the calendar; only admins define it).
 */
class HolidayPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return true;
    }

    public function view(User $actor, Holiday $holiday): bool
    {
        return $actor->role === UserRole::SuperAdmin || $actor->school_id === $holiday->school_id;
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, Holiday $holiday): bool
    {
        return $this->manages($actor, $holiday);
    }

    public function delete(User $actor, Holiday $holiday): bool
    {
        return $this->manages($actor, $holiday);
    }

    private function manages(User $actor, Holiday $holiday): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin && $actor->school_id === $holiday->school_id;
    }
}

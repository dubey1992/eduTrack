<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Period;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Same shape as DepartmentPolicy - SUPER_ADMIN full access, SCHOOL_ADMIN
 * scoped to their own school, every other role read-only (a Teacher needs
 * to see period timings to read their own schedule, never to edit them).
 */
class PeriodPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return true;
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, Period $period): bool
    {
        return $this->manages($actor, $period);
    }

    public function delete(User $actor, Period $period): bool
    {
        return $this->manages($actor, $period);
    }

    private function manages(User $actor, Period $period): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin && SchoolScope::for($actor)->allows($period->school_id);
    }
}

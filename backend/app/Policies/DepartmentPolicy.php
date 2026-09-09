<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Department;
use App\Models\User;

/**
 * Same shape as AcademicYearPolicy - SUPER_ADMIN full access, SCHOOL_ADMIN
 * scoped to their own school, every other role read-only. See CLAUDE.md
 * rules 12 and 15.
 */
class DepartmentPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return true;
    }

    public function view(User $actor, Department $department): bool
    {
        return $actor->role === UserRole::SuperAdmin || $actor->school_id === $department->school_id;
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, Department $department): bool
    {
        return $this->manages($actor, $department);
    }

    public function delete(User $actor, Department $department): bool
    {
        return $this->manages($actor, $department);
    }

    private function manages(User $actor, Department $department): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin && $actor->school_id === $department->school_id;
    }
}

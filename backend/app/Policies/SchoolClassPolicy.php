<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\SchoolClass;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Same shape as AcademicYearPolicy - SUPER_ADMIN full access, SCHOOL_ADMIN
 * scoped to their own school, every other role read-only. Section
 * management piggybacks on this same policy (a class's sections are edited
 * by whoever can edit the class). See CLAUDE.md rules 12 and 15.
 */
class SchoolClassPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return true;
    }

    public function view(User $actor, SchoolClass $schoolClass): bool
    {
        return $actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->allows($schoolClass->school_id);
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, SchoolClass $schoolClass): bool
    {
        return $this->manages($actor, $schoolClass);
    }

    public function delete(User $actor, SchoolClass $schoolClass): bool
    {
        return $this->manages($actor, $schoolClass);
    }

    private function manages(User $actor, SchoolClass $schoolClass): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role->administersSchool() && SchoolScope::for($actor)->allows($schoolClass->school_id);
    }
}

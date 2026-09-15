<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\AcademicYear;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * SUPER_ADMIN manages academic years for every school. SCHOOL_ADMIN manages
 * their own school's years only. Every other role may only read them (they
 * need academic years for filtering in later phases). School scoping is
 * always read from the actor's own `school_id`, never from client input.
 * See CLAUDE.md rules 12 and 15.
 */
class AcademicYearPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return true;
    }

    public function view(User $actor, AcademicYear $academicYear): bool
    {
        return $actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->allows($academicYear->school_id);
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, AcademicYear $academicYear): bool
    {
        return $this->manages($actor, $academicYear);
    }

    public function setCurrent(User $actor, AcademicYear $academicYear): bool
    {
        return $this->manages($actor, $academicYear);
    }

    public function delete(User $actor, AcademicYear $academicYear): bool
    {
        return $this->manages($actor, $academicYear);
    }

    private function manages(User $actor, AcademicYear $academicYear): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin && SchoolScope::for($actor)->allows($academicYear->school_id);
    }
}

<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\User;

/**
 * SUPER_ADMIN manages every user, across every school. SCHOOL_ADMIN
 * manages users within their own school only, and never another admin
 * account (SUPER_ADMIN or SCHOOL_ADMIN) - only the operational roles
 * (HOD/TEACHER/STAFF/TRANSPORT_MANAGER). School scoping is always read
 * from the actor's own `school_id`, never from client input.
 * See CLAUDE.md rules 12 and 15.
 */
class UserPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function view(User $actor, User $target): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $this->isSchoolAdminOfSameSchool($actor, $target);
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, User $target): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $this->isSchoolAdminOfSameSchool($actor, $target)
            && ! in_array($target->role, self::ADMIN_ROLES, true);
    }

    public function setStatus(User $actor, User $target): bool
    {
        // A user can never deactivate/reactivate their own account through
        // this endpoint - avoids accidental self-lockout.
        if ($actor->id === $target->id) {
            return false;
        }

        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $this->isSchoolAdminOfSameSchool($actor, $target)
            && ! in_array($target->role, self::ADMIN_ROLES, true);
    }

    private function isSchoolAdminOfSameSchool(User $actor, User $target): bool
    {
        return $actor->role === UserRole::SchoolAdmin
            && $actor->school_id !== null
            && $actor->school_id === $target->school_id;
    }
}

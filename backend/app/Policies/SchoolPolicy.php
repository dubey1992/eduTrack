<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;

/**
 * Schools are platform-level records - only SUPER_ADMIN manages them.
 * A SCHOOL_ADMIN may view their own school's details (needed for the
 * school details screen) but never another school's, and never edits
 * the school record itself. See CLAUDE.md rule 15.
 */
class SchoolPolicy
{
    public function viewAny(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function view(User $actor, School $school): bool
    {
        return $actor->role === UserRole::SuperAdmin || $actor->school_id === $school->id;
    }

    public function create(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function update(User $actor, School $school): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function setStatus(User $actor, School $school): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }
}

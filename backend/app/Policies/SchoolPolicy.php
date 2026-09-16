<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Schools are platform-level records - only SUPER_ADMIN manages them.
 * A SCHOOL_ADMIN may view the details of any school in their own group
 * (needed for the school details screen and the branch pickers) but never
 * one outside it, and never edits the school record itself. See CLAUDE.md
 * rule 15.
 */
class SchoolPolicy
{
    public function viewAny(User $actor): bool
    {
        // An admin who answers for several branches lists them so they can
        // pick one - SchoolService::paginate() scopes the list to exactly
        // that group. Asked of the scope rather than the role, because a
        // School Admin has branches to pick from only when their school is
        // in a group; a standalone one has nothing to choose and is refused,
        // exactly as before.
        return $actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->coversAGroup();
    }

    public function view(User $actor, School $school): bool
    {
        return $actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->allows($school->id);
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

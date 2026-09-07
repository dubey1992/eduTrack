<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\User;

/**
 * Phase 1: user management is SUPER_ADMIN-only, since schools (and
 * therefore school-scoped SCHOOL_ADMIN access) don't exist yet. Phase 2
 * extends this once `school_id` is introduced. See CLAUDE.md rule 15.
 */
class UserPolicy
{
    public function viewAny(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function view(User $actor, User $target): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function create(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function update(User $actor, User $target): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function setStatus(User $actor, User $target): bool
    {
        if ($actor->role !== UserRole::SuperAdmin) {
            return false;
        }

        // A user can never deactivate/reactivate their own account through
        // this endpoint - avoids accidental self-lockout.
        return $actor->id !== $target->id;
    }
}

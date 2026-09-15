<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\User;

/**
 * Signup requests belong to the platform, not to any school - a school that
 * could read them would be reading its competitors' enquiries. SUPER_ADMIN
 * only, same as onboarding and payments.
 */
class EarlyAccessRequestPolicy
{
    public function viewAny(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function view(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function review(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }
}

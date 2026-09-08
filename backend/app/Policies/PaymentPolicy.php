<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Payment;
use App\Models\User;

/**
 * Payments record what a school has paid the platform - a SUPER_ADMIN-only
 * concern (CLAUDE.md rule 4/47: this is not a school-facing feature).
 */
class PaymentPolicy
{
    public function viewAny(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function view(User $actor, Payment $payment): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function create(User $actor): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }

    public function update(User $actor, Payment $payment): bool
    {
        return $actor->role === UserRole::SuperAdmin;
    }
}

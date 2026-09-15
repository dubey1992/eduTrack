<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Driver;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Same matrix as VehiclePolicy.
 */
class DriverPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, VehiclePolicy::VIEW_ROLES, true);
    }

    public function view(User $actor, Driver $driver): bool
    {
        return $this->viewAny($actor)
            && ($actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->allows($driver->school_id));
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, Driver $driver): bool
    {
        return $this->manages($actor, $driver);
    }

    public function delete(User $actor, Driver $driver): bool
    {
        return $this->manages($actor, $driver);
    }

    private function manages(User $actor, Driver $driver): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin && SchoolScope::for($actor)->allows($driver->school_id);
    }
}

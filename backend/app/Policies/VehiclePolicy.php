<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\User;
use App\Models\Vehicle;
use App\Support\SchoolScope;

/**
 * Transport master data follows the prototype's permission matrix:
 * Admin "Full", HOD/Teacher/Transport Manager "View" (the Transport
 * Manager's own powers arrive with trips in Phase 15), Staff none.
 */
class VehiclePolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin];

    public const VIEW_ROLES = [
        UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin, UserRole::Hod, UserRole::Teacher,
        UserRole::TransportManager,
    ];

    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, self::VIEW_ROLES, true);
    }

    public function view(User $actor, Vehicle $vehicle): bool
    {
        return $this->viewAny($actor)
            && ($actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->allows($vehicle->school_id));
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, Vehicle $vehicle): bool
    {
        return $this->manages($actor, $vehicle);
    }

    public function delete(User $actor, Vehicle $vehicle): bool
    {
        return $this->manages($actor, $vehicle);
    }

    private function manages(User $actor, Vehicle $vehicle): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role->administersSchool() && SchoolScope::for($actor)->allows($vehicle->school_id);
    }
}

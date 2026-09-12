<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\TransportRoute;
use App\Models\TransportTrip;
use App\Models\User;

/**
 * Trips are the Transport Manager's job (the prototype's "Manage Trips"),
 * shared with the admins; HOD/Teacher can follow along read-only; Staff
 * has no transport access.
 */
class TransportTripPolicy
{
    private const MANAGE_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin, UserRole::TransportManager];

    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, VehiclePolicy::VIEW_ROLES, true);
    }

    public function view(User $actor, TransportTrip $trip): bool
    {
        return $this->viewAny($actor) && $this->sameSchoolOrSuper($actor, $trip->school_id);
    }

    public function create(User $actor, TransportRoute $route): bool
    {
        return in_array($actor->role, self::MANAGE_ROLES, true) && $this->sameSchoolOrSuper($actor, $route->school_id);
    }

    /**
     * Reaching stops, boarding/dropping riders, ending and cancelling.
     */
    public function manage(User $actor, TransportTrip $trip): bool
    {
        return in_array($actor->role, self::MANAGE_ROLES, true) && $this->sameSchoolOrSuper($actor, $trip->school_id);
    }

    private function sameSchoolOrSuper(User $actor, int $schoolId): bool
    {
        return $actor->role === UserRole::SuperAdmin || $actor->school_id === $schoolId;
    }
}

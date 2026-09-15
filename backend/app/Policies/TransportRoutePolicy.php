<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\TransportRoute;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Same matrix as VehiclePolicy, plus `viewStudents` - the list of students
 * riding a route is the prototype's "Transport Students" access, which
 * only admins and the Transport Manager get (a Teacher's student access
 * stays limited to their own class, see StudentPolicy).
 */
class TransportRoutePolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, VehiclePolicy::VIEW_ROLES, true);
    }

    public function view(User $actor, TransportRoute $route): bool
    {
        return $this->viewAny($actor) && $this->sameSchoolOrSuper($actor, $route);
    }

    public function viewStudents(User $actor, TransportRoute $route): bool
    {
        return in_array($actor->role, [...self::ADMIN_ROLES, UserRole::TransportManager], true)
            && $this->sameSchoolOrSuper($actor, $route);
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, TransportRoute $route): bool
    {
        return $this->manages($actor, $route);
    }

    public function delete(User $actor, TransportRoute $route): bool
    {
        return $this->manages($actor, $route);
    }

    private function manages(User $actor, TransportRoute $route): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role === UserRole::SchoolAdmin && SchoolScope::for($actor)->allows($route->school_id);
    }

    private function sameSchoolOrSuper(User $actor, TransportRoute $route): bool
    {
        return $actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->allows($route->school_id);
    }
}

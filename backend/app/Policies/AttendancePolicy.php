<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\User;

/**
 * Coarse role gate for the attendance history list - same role set as
 * StudentPolicy::viewAny (SUPER_ADMIN, SCHOOL_ADMIN, TEACHER). The
 * fine-grained school/class scoping happens in AttendanceService::paginate,
 * the same belt-and-suspenders split StudentService uses.
 */
class AttendancePolicy
{
    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin, UserRole::Teacher], true);
    }
}

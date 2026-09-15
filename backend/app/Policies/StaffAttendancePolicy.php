<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Coarse role gate plus school ownership - same shape as
 * ClassSectionPolicy/AttendancePolicy. An HOD is allowed to reach the
 * endpoint for their own school; StaffAttendanceService is what actually
 * narrows their view down to the department(s) they head, the same
 * belt-and-suspenders split used for a Teacher's class-section attendance.
 */
class StaffAttendancePolicy
{
    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin, UserRole::Hod], true);
    }

    public function manage(User $actor, School $school): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return in_array($actor->role, [UserRole::GroupAdmin, UserRole::SchoolAdmin, UserRole::Hod], true)
            && SchoolScope::for($actor)->allows($school->id);
    }
}

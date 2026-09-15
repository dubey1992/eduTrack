<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\TimetableEntry;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Same shape as StaffAttendancePolicy - a coarse role gate for viewing (a
 * Teacher/HOD needs to see the grid to read their own schedule), and a
 * school-scoped `manage` ability for editing, checked against a School
 * rather than an entry since an "upsert" call may be creating one for the
 * first time. Matches the other academic-config policies
 * (Department/Subject/SchoolClass): only SUPER_ADMIN/SCHOOL_ADMIN edit.
 */
class TimetableEntryPolicy
{
    public function viewAny(User $actor): bool
    {
        return true;
    }

    public function manage(User $actor, School $school): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role->administersSchool() && SchoolScope::for($actor)->allows($school->id);
    }

    public function delete(User $actor, TimetableEntry $entry): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role->administersSchool() && SchoolScope::for($actor)->allows($entry->school_id);
    }
}

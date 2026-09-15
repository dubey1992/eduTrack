<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\DailyTeachingReport;
use App\Models\TimetableEntry;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * "Create" and "review" are deliberately separate abilities (same split as
 * StaffLeavePolicy) - filing a report is self-service for whoever actually
 * taught the period, reviewing is an HOD/admin action on someone else's
 * report, and a single actor is never both for the same report.
 */
class DailyTeachingReportPolicy
{
    /**
     * Unlike StaffLeave, this isn't open to every role - Staff/Transport
     * Manager have no legitimate reason to browse teaching reports at all
     * (they're never a scheduled teacher). DailyTeachingReportService's
     * scoped query further narrows this down to "my own" vs "my
     * department" vs "my school" vs "everything".
     */
    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, [UserRole::SuperAdmin, UserRole::SchoolAdmin, UserRole::Hod, UserRole::Teacher], true);
    }

    /**
     * Role AND ownership - being a Teacher/HOD is necessary but not
     * sufficient, the actor must also be the entry's assigned teacher.
     * Both fold into the same 403 (this is genuinely an authorization
     * concern - "assigned to teach this period" is ownership, same as a
     * Teacher assigned to 8A being blocked from 9A attendance), unlike
     * StaffLeave's StaffProfileRequiredException which is a data
     * precondition on an otherwise-permitted actor.
     */
    public function create(User $actor, TimetableEntry $entry): bool
    {
        if (! in_array($actor->role, [UserRole::Teacher, UserRole::Hod], true)) {
            return false;
        }

        return $entry->teacher_id === $actor->id;
    }

    public function review(User $actor, DailyTeachingReport $report): bool
    {
        // Nobody reviews their own report, regardless of role - an HOD
        // heads the same department they teach in, so without this check
        // they'd pass the department-match test below for their own report.
        if ($report->teacher_id === $actor->id) {
            return false;
        }

        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        if ($actor->role === UserRole::SchoolAdmin) {
            return SchoolScope::for($actor)->allows($report->school_id);
        }

        if ($actor->role === UserRole::Hod) {
            return $report->teacher->staffProfile?->department?->hod_user_id === $actor->id;
        }

        return false;
    }
}

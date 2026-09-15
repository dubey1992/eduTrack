<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * SUPER_ADMIN manages every user, across every school. SCHOOL_ADMIN
 * manages non-admin users within their own school freely, and admin-tier
 * accounts (SCHOOL_ADMIN role) on a strict hierarchy: the head (a School
 * Admin who is not themselves a Sub Admin) manages the Sub Admins in their
 * own school, but never another head, and never themselves through this
 * ability. A Sub Admin manages no admin-tier account at all - not even
 * another Sub Admin. School scoping is always read from the actor's own
 * `school_id`, never from client input.
 *
 * `is_sub_admin` distinguishes two tiers of the same SCHOOL_ADMIN role
 * (not a separate UserRole case, so every other policy in the app treats
 * them identically): a School Admin a SUPER_ADMIN onboarded can create
 * further admin accounts for their school ("Sub Admins"); a Sub Admin has
 * the same permissions everywhere else, but can never create any admin
 * account itself. Operational staff (HOD/TEACHER/STAFF/TRANSPORT_MANAGER)
 * are onboarded via Teachers & Staff instead, which creates both the
 * login and the employment record (StaffProfile) together - a Teacher/etc.
 * created through this screen would have no StaffProfile and be invisible
 * to Attendance/Leave, so that path is deliberately not offered here.
 * See CLAUDE.md rules 12 and 15.
 */
class UserPolicy
{
    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin], true);
    }

    public function view(User $actor, User $target): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $this->isSchoolAdminOfSameSchool($actor, $target);
    }

    public function create(User $actor): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role->administersSchool() && ! $actor->is_sub_admin;
    }

    public function update(User $actor, User $target): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $this->manages($actor, $target);
    }

    public function setStatus(User $actor, User $target): bool
    {
        // A user can never deactivate/reactivate their own account through
        // this endpoint - avoids accidental self-lockout.
        if ($actor->id === $target->id) {
            return false;
        }

        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $this->manages($actor, $target);
    }

    /**
     * A School Admin manages any non-admin account in their own school
     * freely. For an admin-tier target (SCHOOL_ADMIN role), only the head
     * (non-Sub) manages it, and only when the target is a Sub Admin - a
     * head never manages another head, and a Sub Admin never manages any
     * admin-tier account, including another Sub Admin.
     */
    private function manages(User $actor, User $target): bool
    {
        if (! $this->isSchoolAdminOfSameSchool($actor, $target)) {
            return false;
        }

        // Admin-tier targets - a School Admin or a Group Admin - are managed
        // on the strict hierarchy below. Everybody else is managed freely
        // within the school.
        if (! $target->role->administersSchool()) {
            return true;
        }

        return ! $actor->is_sub_admin && $target->is_sub_admin;
    }

    private function isSchoolAdminOfSameSchool(User $actor, User $target): bool
    {
        return $actor->role->administersSchool()
            && SchoolScope::for($actor)->allows($target->school_id);
    }
}

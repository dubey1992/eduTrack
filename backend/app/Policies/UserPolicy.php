<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\User;

/**
 * SUPER_ADMIN manages every user, across every school. SCHOOL_ADMIN
 * manages non-admin users within their own school only - an admin-tier
 * account (SCHOOL_ADMIN role, whether a primary School Admin or a Sub
 * Admin) can only ever be updated/deactivated by a SUPER_ADMIN, never even
 * by the School Admin who created it. School scoping is always read from
 * the actor's own `school_id`, never from client input.
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
        return in_array($actor->role, [UserRole::SuperAdmin, UserRole::SchoolAdmin], true);
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

        return $actor->role === UserRole::SchoolAdmin && ! $actor->is_sub_admin;
    }

    public function update(User $actor, User $target): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        // A School Admin manages any non-admin account in their school,
        // but never another admin-tier account - not even a Sub Admin
        // they created themselves. Only a SUPER_ADMIN manages those.
        return $this->isSchoolAdminOfSameSchool($actor, $target) && $target->role !== UserRole::SchoolAdmin;
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

        return $this->isSchoolAdminOfSameSchool($actor, $target) && $target->role !== UserRole::SchoolAdmin;
    }

    private function isSchoolAdminOfSameSchool(User $actor, User $target): bool
    {
        return $actor->role === UserRole::SchoolAdmin
            && $actor->school_id !== null
            && $actor->school_id === $target->school_id;
    }
}

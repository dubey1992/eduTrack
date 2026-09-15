<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\StaffLeave;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * "Apply" and "review" are deliberately separate abilities (unlike
 * StaffAttendancePolicy's single `manage`) - applying is self-service for
 * staff who have their own StaffProfile, reviewing is an admin/HOD action
 * on someone else's request, and a single actor is never both for the same
 * leave.
 */
class StaffLeavePolicy
{
    /**
     * Every role can view leave data - StaffLeaveService::scopedQuery is
     * what actually narrows it down to "my own" vs "my department" vs
     * "my school" vs "everything", so there's no coarse role gate here.
     */
    public function viewAny(User $actor): bool
    {
        return true;
    }

    /**
     * Role only - whether the actor also has a StaffProfile to apply
     * against is a data precondition, not an authorization question, so
     * StaffLeaveController checks that separately and throws
     * StaffProfileRequiredException with a specific, actionable message
     * rather than folding it into a generic 403 here.
     *
     * SCHOOL_ADMIN is included so a School Admin can apply for their own
     * leave too - they get a minimal auto-created StaffProfile on account
     * creation for exactly this (see UserService::create()). SUPER_ADMIN
     * still never applies - they have no school/employment context to
     * apply against.
     */
    public function apply(User $actor): bool
    {
        return in_array(
            $actor->role,
            [UserRole::Teacher, UserRole::Staff, UserRole::Hod, UserRole::TransportManager, UserRole::SchoolAdmin],
            true
        );
    }

    public function review(User $actor, StaffLeave $leave): bool
    {
        // An HOD heads the same department they belong to, so without this
        // check they'd pass the department-match test below for their own
        // leave request - nobody reviews their own leave, regardless of role.
        if ($leave->staff_profile_id === $actor->staffProfile?->id) {
            return false;
        }

        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        if ($actor->role->administersSchool()) {
            return SchoolScope::for($actor)->allows($leave->school_id);
        }

        if ($actor->role === UserRole::Hod) {
            return $leave->staffProfile?->department?->hod_user_id === $actor->id;
        }

        return false;
    }
}

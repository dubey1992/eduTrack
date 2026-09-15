<?php

namespace App\Policies;

use App\Enums\AnnouncementAudience;
use App\Enums\UserRole;
use App\Models\Announcement;
use App\Models\Department;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Admins announce to anyone in their school. A Head of Department may only
 * reach their own department, which is the same boundary they already have
 * over its teaching reports.
 */
class AnnouncementPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return $this->canPublishAtAll($actor);
    }

    public function view(User $actor, Announcement $announcement): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        if (! SchoolScope::for($actor)->allows($announcement->school_id)) {
            return false;
        }

        if ($actor->role === UserRole::Hod) {
            return $announcement->audience_type === AnnouncementAudience::Department
                && $this->headsDepartment($actor, $announcement->audience_id);
        }

        return $actor->role === UserRole::SchoolAdmin;
    }

    /**
     * Publishing is checked against the audience, not just the role.
     */
    public function publish(User $actor, AnnouncementAudience $audience, ?int $target, ?int $schoolId): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        if ($schoolId !== null && ! SchoolScope::for($actor)->allows($schoolId)) {
            return false;
        }

        if ($actor->role === UserRole::SchoolAdmin) {
            return true;
        }

        return $actor->role === UserRole::Hod
            && $audience === AnnouncementAudience::Department
            && $this->headsDepartment($actor, $target);
    }

    public function delete(User $actor, Announcement $announcement): bool
    {
        return $this->view($actor, $announcement);
    }

    public function canPublishAtAll(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true) || $actor->role === UserRole::Hod;
    }

    private function headsDepartment(User $actor, ?int $departmentId): bool
    {
        if ($departmentId === null) {
            return false;
        }

        return Department::query()
            ->whereKey($departmentId)
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query))
            ->where('hod_user_id', $actor->id)
            ->exists();
    }
}

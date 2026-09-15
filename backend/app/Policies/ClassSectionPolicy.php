<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\ClassSection;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Same shape as SchoolClassPolicy - a section is scoped through its parent
 * class's school. See CLAUDE.md rules 12 and 15.
 */
class ClassSectionPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin];

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, ClassSection $section): bool
    {
        return $this->manages($actor, $section);
    }

    public function delete(User $actor, ClassSection $section): bool
    {
        return $this->manages($actor, $section);
    }

    /**
     * Viewing/marking a class's attendance is broader than managing the
     * section itself - the section's own class teacher needs it too, not
     * just SUPER_ADMIN/SCHOOL_ADMIN (see CLAUDE.md rule 12's "a Teacher
     * assigned to 8A must not access 9A attendance" example).
     */
    public function viewAttendance(User $actor, ClassSection $section): bool
    {
        return $this->manages($actor, $section) || $this->isClassTeacher($actor, $section);
    }

    public function markAttendance(User $actor, ClassSection $section): bool
    {
        return $this->viewAttendance($actor, $section);
    }

    private function manages(User $actor, ClassSection $section): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role->administersSchool() && SchoolScope::for($actor)->allows($section->schoolClass->school_id);
    }

    private function isClassTeacher(User $actor, ClassSection $section): bool
    {
        return $actor->role === UserRole::Teacher && $actor->id === $section->class_teacher_id;
    }
}

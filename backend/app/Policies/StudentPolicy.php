<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\Student;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * SUPER_ADMIN and SCHOOL_ADMIN manage every student in scope, same shape as
 * UserPolicy/StaffProfilePolicy. TEACHER gets read-only access, and only to
 * students in a class section they are the class teacher of - the
 * "a Teacher assigned to 8A must not access 9A" rule from CLAUDE.md rule 15.
 * HOD/STAFF/TRANSPORT_MANAGER have no student access yet (Phase 6 scope).
 */
class StudentPolicy
{
    private const ADMIN_ROLES = [UserRole::SuperAdmin, UserRole::GroupAdmin, UserRole::SchoolAdmin];

    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, [...self::ADMIN_ROLES, UserRole::Teacher], true);
    }

    public function view(User $actor, Student $student): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        if ($actor->role->administersSchool()) {
            return SchoolScope::for($actor)->allows($student->school_id);
        }

        if ($actor->role === UserRole::Teacher) {
            return $student->classSection?->class_teacher_id === $actor->id;
        }

        return false;
    }

    public function create(User $actor): bool
    {
        return in_array($actor->role, self::ADMIN_ROLES, true);
    }

    public function update(User $actor, Student $student): bool
    {
        return $this->manages($actor, $student);
    }

    public function setStatus(User $actor, Student $student): bool
    {
        return $this->manages($actor, $student);
    }

    private function manages(User $actor, Student $student): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        return $actor->role->administersSchool() && SchoolScope::for($actor)->allows($student->school_id);
    }
}

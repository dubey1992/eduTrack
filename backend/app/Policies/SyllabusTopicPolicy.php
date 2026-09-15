<?php

namespace App\Policies;

use App\Enums\UserRole;
use App\Models\ClassSection;
use App\Models\Subject;
use App\Models\SyllabusTopic;
use App\Models\TimetableEntry;
use App\Models\User;
use App\Support\SchoolScope;

/**
 * Two distinct concerns live here, both keyed off SyllabusTopic since a
 * model can only have one registered policy:
 *
 * - The curriculum outline (what topics exist, in what order) is managed
 *   by whoever manages the subject's academic setup - SUPER_ADMIN,
 *   SCHOOL_ADMIN of the same school, or the HOD of the subject's
 *   department. See create/update/delete.
 * - Marking a topic complete for one class section (see mark()) is
 *   broader - also open to the Teacher actually scheduled to teach that
 *   subject in that section per Phase 10's timetable, not just the
 *   outline managers. Ownership is checked against the live timetable
 *   rather than a stored "assigned teacher" field, so re-assigning a
 *   subject to a different teacher takes effect immediately.
 *
 * Every authenticated role in Teachers & Staff can read the outline and
 * checklist (Teachers need to see what to teach); STAFF/TRANSPORT_MANAGER
 * have no legitimate reason to. See CLAUDE.md rules 12 and 15.
 */
class SyllabusTopicPolicy
{
    public function viewAny(User $actor): bool
    {
        return in_array($actor->role, [UserRole::SuperAdmin, UserRole::SchoolAdmin, UserRole::Hod, UserRole::Teacher], true);
    }

    public function view(User $actor, SyllabusTopic $topic): bool
    {
        return $actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->allows($topic->school_id);
    }

    public function create(User $actor, Subject $subject): bool
    {
        return $this->managesSubject($actor, $subject);
    }

    public function update(User $actor, SyllabusTopic $topic): bool
    {
        return $this->managesSubject($actor, $topic->subject);
    }

    public function delete(User $actor, SyllabusTopic $topic): bool
    {
        return $this->managesSubject($actor, $topic->subject);
    }

    /**
     * Reading a section's checklist - any viewAny()-eligible actor in the
     * same school can see it (a Teacher checking another section's pace
     * isn't a security concern the way editing it would be).
     */
    public function viewChecklist(User $actor, ClassSection $section): bool
    {
        if (! $this->viewAny($actor)) {
            return false;
        }

        return $actor->role === UserRole::SuperAdmin || SchoolScope::for($actor)->allows($section->schoolClass->school_id);
    }

    public function mark(User $actor, SyllabusTopic $topic, ClassSection $section): bool
    {
        $schoolId = $section->schoolClass->school_id;

        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        if (! SchoolScope::for($actor)->allows($schoolId)) {
            return false;
        }

        if ($actor->role === UserRole::SchoolAdmin) {
            return true;
        }

        if ($actor->role === UserRole::Hod) {
            return $topic->subject->department?->hod_user_id === $actor->id;
        }

        if ($actor->role === UserRole::Teacher) {
            return TimetableEntry::query()
                ->where('class_section_id', $section->id)
                ->where('subject_id', $topic->subject_id)
                ->where('teacher_id', $actor->id)
                ->exists();
        }

        return false;
    }

    private function managesSubject(User $actor, Subject $subject): bool
    {
        if ($actor->role === UserRole::SuperAdmin) {
            return true;
        }

        if (! SchoolScope::for($actor)->allows($subject->school_id)) {
            return false;
        }

        if ($actor->role === UserRole::SchoolAdmin) {
            return true;
        }

        if ($actor->role === UserRole::Hod) {
            return $subject->department?->hod_user_id === $actor->id;
        }

        return false;
    }
}

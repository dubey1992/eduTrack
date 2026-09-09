<?php

namespace App\Services;

use App\Exceptions\TeacherScheduleConflictException;
use App\Models\ClassSection;
use App\Models\TimetableEntry;
use App\Models\User;
use Illuminate\Support\Collection;

class TimetableService
{
    private const array RELATIONS = ['classSection.schoolClass', 'period', 'subject', 'teacher'];

    /**
     * A class section's full Mon-Fri x period grid - every entry it
     * currently has, for the caller to lay out against the school's
     * periods however the UI wants (a grid, a list, etc).
     *
     * @return Collection<int, TimetableEntry>
     */
    public function forClassSection(ClassSection $classSection): Collection
    {
        return TimetableEntry::query()
            ->where('class_section_id', $classSection->id)
            ->with(self::RELATIONS)
            ->get();
    }

    /**
     * One teacher's own schedule across every class section they teach -
     * "my timetable", the same grid shape as forClassSection() but sliced
     * the other way.
     *
     * @return Collection<int, TimetableEntry>
     */
    public function forTeacher(User $teacher): Collection
    {
        return TimetableEntry::query()
            ->where('teacher_id', $teacher->id)
            ->with(self::RELATIONS)
            ->get();
    }

    /**
     * Creates or replaces the single class-section/day/period cell this
     * data identifies - matches the prototype's "Edit Timetable" grid,
     * edited one cell at a time rather than submitted as a whole week.
     *
     * @param  array<string, mixed>  $data
     */
    public function upsertEntry(array $data): TimetableEntry
    {
        $this->assertNoTeacherConflict($data);

        $entry = TimetableEntry::updateOrCreate(
            [
                'class_section_id' => $data['class_section_id'],
                'period_id' => $data['period_id'],
                'day_of_week' => $data['day_of_week'],
            ],
            [
                'school_id' => $data['school_id'],
                'subject_id' => $data['subject_id'],
                'teacher_id' => $data['teacher_id'],
            ]
        );

        return $entry->load(self::RELATIONS);
    }

    public function deleteEntry(TimetableEntry $entry): void
    {
        $entry->delete();
    }

    /**
     * A teacher can't teach two class sections in the same period on the
     * same day - the one conflict the class-section-scoped unique
     * constraint on timetable_entries can't catch by itself, since it only
     * guards one class section at a time.
     *
     * @param  array<string, mixed>  $data
     */
    private function assertNoTeacherConflict(array $data): void
    {
        $conflict = TimetableEntry::query()
            ->where('teacher_id', $data['teacher_id'])
            ->where('day_of_week', $data['day_of_week'])
            ->where('period_id', $data['period_id'])
            ->where('class_section_id', '!=', $data['class_section_id'])
            ->exists();

        if ($conflict) {
            throw new TeacherScheduleConflictException(
                'This teacher is already scheduled for another class section at this day and period.'
            );
        }
    }
}

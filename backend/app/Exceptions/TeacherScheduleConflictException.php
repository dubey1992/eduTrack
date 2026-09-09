<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a timetable entry would put the same teacher in two class
 * sections at the same day and period - the one conflict the class-
 * section-scoped unique constraint on timetable_entries can't catch on
 * its own. See TimetableService::assertNoTeacherConflict().
 */
class TeacherScheduleConflictException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

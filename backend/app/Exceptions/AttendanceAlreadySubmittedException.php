<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a bulk attendance submission targets a class section/date that
 * already has attendance recorded - the day is locked to a single initial
 * submission, corrections go through the explicit update endpoint instead.
 * See CLAUDE.md rule 16 (API Standards) for the exact error shape.
 */
class AttendanceAlreadySubmittedException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a teacher submits a second report for a timetable entry/date
 * that already has one - one report per scheduled occurrence, corrections
 * happen by contacting whoever reviews it, not by re-submitting.
 */
class TeachingReportAlreadySubmittedException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

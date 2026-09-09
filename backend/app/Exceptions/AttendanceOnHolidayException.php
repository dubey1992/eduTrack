<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when student or staff attendance is submitted for a date on the
 * school's holiday calendar - nobody is expected in, so there is nothing
 * to mark.
 */
class AttendanceOnHolidayException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

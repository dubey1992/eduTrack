<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a daily teaching report is filed for a date on the school's
 * holiday calendar - no periods are taught on a holiday.
 */
class TeachingReportOnHolidayException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

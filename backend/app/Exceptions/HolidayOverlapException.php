<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a holiday's date range overlaps another holiday in the same
 * school - a date can only ever be one holiday.
 */
class HolidayOverlapException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

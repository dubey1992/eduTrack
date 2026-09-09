<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a leave request covers only weekends and/or holidays - there
 * is no working day to take leave from.
 */
class LeaveOnNonWorkingDaysException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

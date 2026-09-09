<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a staff member applies for leave that overlaps a date range
 * they already have a pending or approved request for - a staff member's
 * leave history should never carry two live requests for the same day.
 */
class LeaveOverlapException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

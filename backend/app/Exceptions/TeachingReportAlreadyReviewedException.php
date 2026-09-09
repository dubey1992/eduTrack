<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when review() is attempted on a report that already has a
 * reviewer - prevents a second reviewer silently overwriting who actually
 * reviewed it first.
 */
class TeachingReportAlreadyReviewedException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

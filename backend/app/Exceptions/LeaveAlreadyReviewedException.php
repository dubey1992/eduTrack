<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when approve/reject is attempted on a leave request that has
 * already been reviewed - a decision is final, corrections happen by
 * applying for a new leave request rather than re-reviewing this one.
 */
class LeaveAlreadyReviewedException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

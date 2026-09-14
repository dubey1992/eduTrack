<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a day's record is submitted for a day the school does not run.
 *
 * A holiday gets its own exception so it can name itself; this covers the
 * other half of the same rule - weekends. Both had to be enforced, because
 * every working-day figure in the product already excludes both, and a
 * Saturday register that no percentage counts is worse than no register.
 */
class NonWorkingDayException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a role that's allowed to apply for leave (Teacher/Staff/HOD/
 * Transport Manager) has no linked StaffProfile yet - a data precondition,
 * not an authorization failure, so it gets its own actionable error rather
 * than a generic 403 that leaves the user guessing why. See
 * StaffLeaveController::store().
 */
class StaffProfileRequiredException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

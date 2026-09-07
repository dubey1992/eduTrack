<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a user with correct credentials attempts to log in while
 * their account is deactivated. See CLAUDE.md rule 11 (user
 * activation/deactivation).
 */
class AccountInactiveException extends Exception
{
    public function __construct()
    {
        parent::__construct('This account has been deactivated. Contact your school administrator.');
    }
}

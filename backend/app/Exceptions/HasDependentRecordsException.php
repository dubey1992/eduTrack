<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when deleting a record would orphan rows that depend on it (e.g. a
 * department that still has subjects). Surfaced as a clean 409 instead of a
 * raw SQL foreign-key-constraint error - see CLAUDE.md rule 16.
 */
class HasDependentRecordsException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

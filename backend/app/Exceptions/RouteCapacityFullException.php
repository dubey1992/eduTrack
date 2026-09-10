<?php

namespace App\Exceptions;

use Exception;

/**
 * Thrown when a student is assigned to a route whose vehicle already has
 * as many students as it has seats.
 */
class RouteCapacityFullException extends Exception
{
    public function __construct(string $message)
    {
        parent::__construct($message);
    }
}

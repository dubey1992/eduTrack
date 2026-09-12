<?php

namespace App\Exceptions;

use Exception;

/**
 * A transport-trip workflow rule was violated (409). The code names the
 * rule so the client can react to specific ones; the message is what the
 * user sees.
 */
class TripRuleException extends Exception
{
    public function __construct(public readonly string $errorCode, string $message)
    {
        parent::__construct($message);
    }

    public static function routeNotReady(string $routeName): self
    {
        return new self('ROUTE_NOT_READY', "{$routeName} needs an active vehicle and driver before a trip can start.");
    }

    public static function nonWorkingDay(): self
    {
        return new self('TRIP_ON_NON_WORKING_DAY', 'Trips do not run on weekends or holidays.');
    }

    public static function alreadyInProgress(string $routeName): self
    {
        return new self('TRIP_ALREADY_IN_PROGRESS', "{$routeName} already has a trip in progress. End or cancel it first.");
    }

    public static function alreadyExists(string $routeName, string $direction): self
    {
        return new self('TRIP_ALREADY_EXISTS', "Today's {$direction} trip for {$routeName} has already been run.");
    }

    public static function notInProgress(): self
    {
        return new self('TRIP_NOT_IN_PROGRESS', 'This trip is no longer in progress.');
    }

    public static function ridersOnBoard(int $count): self
    {
        $noun = $count === 1 ? 'student is' : 'students are';

        return new self('TRIP_RIDERS_ON_BOARD', "{$count} {$noun} still on board. Drop them off before ending the trip.");
    }

    public static function invalidRiderChange(string $from, string $to): self
    {
        return new self('INVALID_RIDER_STATUS_CHANGE', "A {$from} student cannot be marked {$to}.");
    }
}

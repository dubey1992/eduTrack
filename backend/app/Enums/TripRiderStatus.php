<?php

namespace App\Enums;

/**
 * pending -> boarded -> dropped is the happy path; pending -> absent when
 * the student never showed up. Nothing moves backwards.
 */
enum TripRiderStatus: string
{
    case Pending = 'pending';
    case Boarded = 'boarded';
    case Dropped = 'dropped';
    case Absent = 'absent';

    public function canBecome(self $next): bool
    {
        return match ($this) {
            self::Pending => $next === self::Boarded || $next === self::Absent,
            self::Boarded => $next === self::Dropped,
            self::Dropped, self::Absent => false,
        };
    }
}

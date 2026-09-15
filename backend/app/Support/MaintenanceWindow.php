<?php

namespace App\Support;

use Carbon\CarbonImmutable;
use Throwable;

/**
 * When a scheduled maintenance window is expected to end.
 *
 * Whoever takes the platform down sets MAINTENANCE_UNTIL in .env before
 * running `php artisan down`; the maintenance page then says when to come
 * back instead of the useless "shortly". Leaving it unset is fine - the page
 * simply says less rather than saying something wrong.
 *
 * Read from the environment rather than from a table on purpose: during
 * maintenance the database is the thing most likely to be unavailable.
 */
class MaintenanceWindow
{
    /**
     * The end of the window, as a person should read it - in the platform's
     * timezone and the app's date format.
     *
     * Null when nothing is set, when the value cannot be read as a date, or
     * when the time it names has already passed (a stale value left in .env
     * from the last window would otherwise promise a return time in the
     * past, which reads as broken rather than as late).
     */
    public static function endsAtLabel(): ?string
    {
        $configured = config('app.maintenance_until');

        if (! is_string($configured) || trim($configured) === '') {
            return null;
        }

        try {
            $endsAt = CarbonImmutable::parse(trim($configured));
        } catch (Throwable) {
            return null;
        }

        if ($endsAt->isPast()) {
            return null;
        }

        $clock = SchoolClock::platform();

        return $clock->format($endsAt, DateFormats::DATE_TIME).' '.$clock->timezone();
    }
}

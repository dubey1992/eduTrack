<?php

namespace App\Support;

use Illuminate\Support\Carbon;

class WorkingHours
{
    /**
     * Formats a check-in/check-out pair (e.g. "08:05", "15:30") as "7h 25m",
     * or null if either side is missing.
     */
    public static function format(?string $checkIn, ?string $checkOut): ?string
    {
        if ($checkIn === null || $checkOut === null) {
            return null;
        }

        $minutes = Carbon::parse($checkIn)->diffInMinutes(Carbon::parse($checkOut));

        return sprintf('%dh %dm', intdiv($minutes, 60), $minutes % 60);
    }
}

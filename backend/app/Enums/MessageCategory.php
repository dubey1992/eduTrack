<?php

namespace App\Enums;

/**
 * The prototype's filter tabs on the Communication Center log.
 */
enum MessageCategory: string
{
    case Attendance = 'attendance';
    case Transport = 'transport';
    case Leave = 'leave';
    case Announcement = 'announcement';

    public function label(): string
    {
        return ucfirst($this->value);
    }
}

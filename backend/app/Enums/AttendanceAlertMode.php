<?php

namespace App\Enums;

/**
 * The prototype's "Send for" control on the attendance screen.
 */
enum AttendanceAlertMode: string
{
    case Off = 'off';
    case AbsentOnly = 'absent';
    case PresentAndAbsent = 'both';

    public function label(): string
    {
        return match ($this) {
            self::Off => 'No attendance alerts',
            self::AbsentOnly => 'Absent only',
            self::PresentAndAbsent => 'Present + Absent',
        };
    }
}

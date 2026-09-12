<?php

namespace App\Enums;

enum LeaveType: string
{
    case Casual = 'casual';
    case Medical = 'medical';
    case Earned = 'earned';
    case HalfDay = 'half_day';

    public function label(): string
    {
        return match ($this) {
            self::Casual => 'casual',
            self::Medical => 'medical',
            self::Earned => 'earned',
            self::HalfDay => 'half-day',
        };
    }
}

<?php

namespace App\Enums;

enum LeaveType: string
{
    case Casual = 'casual';
    case Medical = 'medical';
    case Earned = 'earned';
    case HalfDay = 'half_day';
}

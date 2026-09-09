<?php

namespace App\Enums;

enum HolidayType: string
{
    case National = 'national';
    case Religious = 'religious';
    case SchoolEvent = 'school_event';
    case Vacation = 'vacation';
}

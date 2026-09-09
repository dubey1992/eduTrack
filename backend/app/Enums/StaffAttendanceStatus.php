<?php

namespace App\Enums;

enum StaffAttendanceStatus: string
{
    case Present = 'present';
    case Absent = 'absent';
    case Leave = 'leave';
    case HalfDay = 'half_day';
}

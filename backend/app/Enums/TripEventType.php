<?php

namespace App\Enums;

enum TripEventType: string
{
    case Started = 'started';
    case StopReached = 'stop_reached';
    case Boarded = 'boarded';
    case Dropped = 'dropped';
    case Absent = 'absent';
    case Completed = 'completed';
    case Cancelled = 'cancelled';
}

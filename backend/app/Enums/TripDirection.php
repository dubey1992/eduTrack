<?php

namespace App\Enums;

enum TripDirection: string
{
    case Pickup = 'pickup';
    case Drop = 'drop';

    public function label(): string
    {
        return $this === self::Pickup ? 'pickup' : 'drop';
    }
}

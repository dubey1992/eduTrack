<?php

namespace App\Enums;

/**
 * Shared by vehicles, drivers and routes - "inactive" keeps the record (and
 * its history) but takes it out of every picker.
 */
enum TransportStatus: string
{
    case Active = 'active';
    case Inactive = 'inactive';
}

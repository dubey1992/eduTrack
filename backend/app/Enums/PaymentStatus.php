<?php

namespace App\Enums;

enum PaymentStatus: string
{
    case Pending = 'pending';
    case Paid = 'paid';
    case Partial = 'partial';
    case Cancelled = 'cancelled';
}

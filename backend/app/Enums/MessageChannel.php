<?php

namespace App\Enums;

/**
 * Push is deliberately absent: it arrives later as another gateway adapter,
 * without a schema change.
 */
enum MessageChannel: string
{
    case Sms = 'sms';
    case InApp = 'in_app';

    public function label(): string
    {
        return $this === self::Sms ? 'SMS' : 'In-app';
    }
}

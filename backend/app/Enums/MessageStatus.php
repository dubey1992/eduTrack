<?php

namespace App\Enums;

enum MessageStatus: string
{
    case Queued = 'queued';
    case Sent = 'sent';
    case Failed = 'failed';
    /** Recorded but never sent - the school switched the alert off, or there was no mobile number. */
    case Skipped = 'skipped';

    public function label(): string
    {
        return ucfirst($this->value);
    }
}

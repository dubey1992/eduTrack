<?php

namespace App\Support\Sms;

/**
 * What a gateway reports back. Never throws at the caller - a failed send is
 * a recorded outcome, not an exception, so one bad number cannot abort a
 * whole attendance submission.
 */
class SmsResult
{
    private function __construct(
        public readonly bool $accepted,
        public readonly ?string $providerMessageId = null,
        public readonly ?string $failureReason = null,
    ) {}

    public static function accepted(?string $providerMessageId = null): self
    {
        return new self(true, $providerMessageId);
    }

    public static function failed(string $reason): self
    {
        return new self(false, null, $reason);
    }
}

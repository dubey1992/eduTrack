<?php

namespace App\Support\Sms;

/**
 * Every SMS provider adapter implements this. Nothing outside this namespace
 * may talk to a provider directly, so swapping Twilio for MSG91 (or adding
 * push later) is a new class plus a config entry.
 */
interface SmsGateway
{
    public function name(): string;

    public function send(string $mobile, string $body, ?string $senderId = null): SmsResult;
}

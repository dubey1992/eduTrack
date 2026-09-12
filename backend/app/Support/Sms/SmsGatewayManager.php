<?php

namespace App\Support\Sms;

use InvalidArgumentException;

/**
 * Resolves the adapter a school's settings ask for, falling back to the
 * configured default when a school names a gateway that is not installed.
 */
class SmsGatewayManager
{
    public function gateway(?string $name = null): SmsGateway
    {
        $name ??= config('communication.default');

        if (! is_string($name) || config("communication.gateways.{$name}") === null) {
            $name = config('communication.default');
        }

        return match (config("communication.gateways.{$name}.driver")) {
            'log' => new LogSmsGateway,
            default => throw new InvalidArgumentException("No SMS gateway adapter is installed for [{$name}]."),
        };
    }

    public function label(?string $name = null): string
    {
        $name ??= config('communication.default');

        return config("communication.gateways.{$name}.label") ?? 'Demo Gateway';
    }
}

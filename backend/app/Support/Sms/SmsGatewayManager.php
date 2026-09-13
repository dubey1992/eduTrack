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
        $name = $this->resolveName($name);

        return match (config("communication.gateways.{$name}.driver")) {
            'log' => new LogSmsGateway,
            default => throw new InvalidArgumentException("No SMS gateway adapter is installed for [{$name}]."),
        };
    }

    /**
     * Whether this gateway actually sends anything. The demo gateway does
     * not, and a school must never be left reading "Sent" and assuming a
     * parent was told.
     */
    public function delivers(?string $name = null): bool
    {
        $name = $this->resolveName($name);

        return (bool) (config("communication.gateways.{$name}.delivers") ?? true);
    }

    public function label(?string $name = null): string
    {
        $name = $this->resolveName($name);

        return config("communication.gateways.{$name}.label") ?? 'Demo Gateway';
    }

    /**
     * The gateway that will really be used.
     *
     * A school can hold the name of a gateway that is no longer installed -
     * one removed from config, say - and sending falls back to the default.
     * Every question about the gateway has to be answered about that same
     * fallback, or the app could report a provider it is not actually using.
     */
    private function resolveName(?string $name): string
    {
        if (! is_string($name) || config("communication.gateways.{$name}") === null) {
            return (string) config('communication.default');
        }

        return $name;
    }
}

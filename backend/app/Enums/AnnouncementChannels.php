<?php

namespace App\Enums;

/**
 * The prototype's channel picker: "SMS + In-app", "SMS Only", "In-app Only".
 */
enum AnnouncementChannels: string
{
    case SmsAndInApp = 'sms_in_app';
    case SmsOnly = 'sms';
    case InAppOnly = 'in_app';

    public function label(): string
    {
        return match ($this) {
            self::SmsAndInApp => 'SMS + In-app',
            self::SmsOnly => 'SMS Only',
            self::InAppOnly => 'In-app Only',
        };
    }

    public function includesSms(): bool
    {
        return $this !== self::InAppOnly;
    }

    public function includesInApp(): bool
    {
        return $this !== self::SmsOnly;
    }

    /**
     * @return array<int, MessageChannel>
     */
    public function messageChannels(): array
    {
        return match ($this) {
            self::SmsAndInApp => [MessageChannel::InApp, MessageChannel::Sms],
            self::SmsOnly => [MessageChannel::Sms],
            self::InAppOnly => [MessageChannel::InApp],
        };
    }
}

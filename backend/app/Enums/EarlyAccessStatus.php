<?php

namespace App\Enums;

/**
 * Where a signup request has got to.
 *
 * Deliberately a short pipeline rather than a free-text field: the panel has
 * to be able to say what is waiting on somebody, and "Converted" has to be
 * something the system sets rather than something a person remembers to.
 */
enum EarlyAccessStatus: string
{
    /** Just arrived. Nobody has looked at it. */
    case New = 'new';

    /** Somebody has been in touch. */
    case Contacted = 'contacted';

    /** A school was onboarded from this request - set when that happens. */
    case Converted = 'converted';

    /** Not going ahead. */
    case Declined = 'declined';

    public function label(): string
    {
        return match ($this) {
            self::New => 'New',
            self::Contacted => 'Contacted',
            self::Converted => 'Converted',
            self::Declined => 'Declined',
        };
    }

    /**
     * The statuses a person may set by hand.
     *
     * Converted is not among them: it means a school exists, and saying so
     * without one would make the list disagree with reality.
     *
     * @return array<int, string>
     */
    public static function settable(): array
    {
        return [self::New->value, self::Contacted->value, self::Declined->value];
    }

    /** True while the request is still somebody's to deal with. */
    public function isOpen(): bool
    {
        return $this === self::New || $this === self::Contacted;
    }
}

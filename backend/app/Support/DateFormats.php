<?php

namespace App\Support;

/**
 * How a date is written wherever a person reads one.
 *
 * US order - 09/17/2026 - on every screen, in every message and on the PDF
 * receipt, so a parent's text agrees with the log entry behind it. Kept in one
 * place because these strings were scattered across six services and a Blade
 * template, and a format that lives in seven places is a format that drifts.
 *
 * This is presentation only. Dates on the wire and in the database stay ISO
 * (Y-m-d), which is what every API and every `date` column expects.
 */
class DateFormats
{
    /** 09/17/2026 */
    public const string DATE = 'm/d/Y';

    /** 7:42 AM */
    public const string TIME = 'g:i A';

    /** 09/17/2026 7:42 AM */
    public const string DATE_TIME = 'm/d/Y g:i A';

    /**
     * The ways a spreadsheet writes the same date, for `date_format` on a
     * bulk import. Excel drops the leading zeros - 9/14/2026 - unless the
     * column happens to be formatted otherwise, and either is what the
     * person typing meant.
     */
    public const string INPUT_DATES = 'm/d/Y,n/j/Y';

    /**
     * Turns a date written the way people write them into the ISO date a
     * `date` column stores.
     *
     * Only ever called on a value that has already passed `date_format`
     * against INPUT_DATES, so a null return means the caller skipped that.
     */
    public static function toIso(string $value): ?string
    {
        foreach (explode(',', self::INPUT_DATES) as $format) {
            $date = \DateTimeImmutable::createFromFormat('!'.$format, trim($value));

            if ($date !== false) {
                return $date->format('Y-m-d');
            }
        }

        return null;
    }
}

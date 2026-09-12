<?php

namespace App\Support;

use App\Enums\UserRole;
use App\Models\School;
use App\Models\User;
use DateTimeInterface;
use Illuminate\Support\Carbon;

/**
 * What time it is for one school.
 *
 * Schools run in different countries, so "today" is not a property of the
 * server. Two rules keep this honest everywhere in the codebase:
 *
 *  - An instant (started_at, sent_at, created_at) is stored in UTC. It is a
 *    moment in time and does not belong to a timezone; only its *rendering*
 *    does, which is what format() is for.
 *  - A calendar date (attendance_date, payment_date, a holiday) is whatever
 *    the date was *at the school*. That is what today() and date() answer.
 *
 * Platform-level views belong to no school - the Super Admin's cross-school
 * totals, for instance - and use platform() instead, which follows the
 * APP_TIMEZONE config.
 */
class SchoolClock
{
    private function __construct(private readonly string $timezone) {}

    /**
     * The clock for a school. A null school (a Super Admin, or a record with
     * no school attached) falls back to the platform clock rather than
     * guessing a zone.
     */
    public static function for(School|int|null $school): self
    {
        if ($school === null) {
            return self::platform();
        }

        $timezone = $school instanceof School
            ? $school->timezone
            : School::query()->whereKey($school)->value('timezone');

        return new self(self::sanitize($timezone));
    }

    /**
     * The clock for whichever school a user belongs to. A Super Admin belongs
     * to none, so they get the platform clock.
     */
    public static function forUser(?User $user): self
    {
        return self::for($user?->school_id);
    }

    /**
     * The clock a scoped listing should be read on.
     *
     * A school user always means their own school. A Super Admin means
     * whichever school they have filtered to, or the platform's zone when
     * they are looking across all of them - "today" across four countries
     * cannot be any one school's today.
     */
    public static function forScope(User $actor, int|string|null $schoolId): self
    {
        if ($actor->role !== UserRole::SuperAdmin) {
            return self::for($actor->school_id);
        }

        return $schoolId === null || $schoolId === '' ? self::platform() : self::for((int) $schoolId);
    }

    /**
     * The platform's own zone, for the few views that belong to no school -
     * the Super Admin's cross-school totals. Deliberately not app.timezone,
     * which must stay UTC because it decides how instants are stored.
     */
    public static function platform(): self
    {
        return new self(self::sanitize(config('app.platform_timezone')));
    }

    public function timezone(): string
    {
        return $this->timezone;
    }

    /**
     * Now, as the school experiences it.
     */
    public function now(): Carbon
    {
        return Carbon::now($this->timezone);
    }

    /**
     * Midnight at the start of the school's current day.
     */
    public function today(): Carbon
    {
        return $this->now()->startOfDay();
    }

    /**
     * The school's current calendar date as Y-m-d - the value that belongs in
     * a date column, and the one to compare date columns against.
     */
    public function date(): string
    {
        return $this->now()->toDateString();
    }

    /**
     * Reads an instant in the school's zone, so it can be asked what day it
     * was there. Returns null for a null instant so callers can pass a
     * nullable column straight through.
     */
    public function toLocal(?DateTimeInterface $instant): ?Carbon
    {
        return $instant === null ? null : Carbon::instance($instant)->setTimezone($this->timezone);
    }

    /**
     * Renders an instant the way the school would read it. Every timestamp
     * shown to a user or written into a message goes through here, so the
     * clock on the screen agrees with the clock on the wall.
     */
    public function format(?DateTimeInterface $instant, string $format): ?string
    {
        return $this->toLocal($instant)?->format($format);
    }

    /**
     * Midnight at the start of a school-local date, expressed in UTC - the
     * value to compare a stored timestamp against.
     *
     * Timestamp columns hold UTC instants, so "created today" cannot be
     * written as whereDate(created_at, '2026-09-12'): for a school in
     * Asia/Kolkata that day begins at 18:30 UTC on the 11th. Every
     * timestamp-versus-date comparison goes through this pair instead.
     */
    public function startOfDayUtc(string|DateTimeInterface $date): Carbon
    {
        $day = $date instanceof DateTimeInterface
            ? Carbon::instance($date)->format('Y-m-d')
            : substr(trim($date), 0, 10);

        return Carbon::createFromFormat('Y-m-d H:i:s', $day.' 00:00:00', $this->timezone)->utc();
    }

    /**
     * The exclusive upper bound of a school-local date, in UTC. Half-open on
     * purpose: `< endOfDayUtc` has no sub-second gap the way `<= 23:59:59`
     * does.
     */
    public function endOfDayUtc(string|DateTimeInterface $date): Carbon
    {
        return $this->startOfDayUtc($date)->addDay();
    }

    /**
     * The UTC window covering one school-local day, as [start, endExclusive].
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    public function dayRange(string|DateTimeInterface $date): array
    {
        return [$this->startOfDayUtc($date), $this->endOfDayUtc($date)];
    }

    /**
     * The UTC window covering the school's current day.
     *
     * @return array{0: Carbon, 1: Carbon}
     */
    public function todayRange(): array
    {
        return $this->dayRange($this->date());
    }

    /**
     * Guards against a zone that is empty or no longer valid (an IANA name
     * can be retired between PHP releases). Falling back to UTC keeps the
     * request working instead of throwing on every date it touches.
     */
    private static function sanitize(?string $timezone): string
    {
        if ($timezone === null || $timezone === '') {
            return 'UTC';
        }

        return in_array($timezone, timezone_identifiers_list(), strict: true) ? $timezone : 'UTC';
    }
}

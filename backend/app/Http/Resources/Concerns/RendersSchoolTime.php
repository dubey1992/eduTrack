<?php

namespace App\Http\Resources\Concerns;

use App\Support\DateFormats;
use App\Support\SchoolClock;
use DateTimeInterface;
use LogicException;

/**
 * Renders stored instants as the school would read them.
 *
 * Timestamps travel as UTC, and the client has no timezone database to
 * convert them with, so every human-readable time is formatted here. A
 * parent resource that has already resolved its clock passes it down with
 * usingClock(), which keeps a trip's forty riders from each looking their
 * own school up.
 */
trait RendersSchoolTime
{
    private ?SchoolClock $schoolClock = null;

    public function usingClock(SchoolClock $clock): static
    {
        $this->schoolClock = $clock;

        return $this;
    }

    protected function clock(): SchoolClock
    {
        if ($this->schoolClock !== null) {
            return $this->schoolClock;
        }

        if ($this->resource->relationLoaded('school')) {
            return $this->schoolClock = SchoolClock::for($this->resource->school);
        }

        $schoolId = $this->resource->school_id ?? null;

        if ($schoolId === null) {
            // Falling back to the platform zone here would quietly print the
            // wrong time - e.g. a trip rider, which carries no school of its
            // own. Whoever renders it has to hand the clock down.
            throw new LogicException(static::class.' has no school to read times against; pass one with usingClock().');
        }

        return $this->schoolClock = SchoolClock::for($schoolId);
    }

    /**
     * "7:42 AM" at the school.
     */
    protected function timeLabel(?DateTimeInterface $instant): ?string
    {
        return $this->clock()->format($instant, DateFormats::TIME);
    }

    /**
     * "12 Sep 2026" at the school.
     */
    protected function dateLabel(?DateTimeInterface $instant): ?string
    {
        return $this->clock()->format($instant, DateFormats::DATE);
    }

    /**
     * "12 Sep 2026, 7:42 AM" at the school.
     */
    protected function dateTimeLabel(?DateTimeInterface $instant): ?string
    {
        return $this->clock()->format($instant, DateFormats::DATE_TIME);
    }
}

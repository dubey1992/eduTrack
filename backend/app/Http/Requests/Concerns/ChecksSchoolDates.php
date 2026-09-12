<?php

namespace App\Http\Requests\Concerns;

use App\Support\SchoolClock;

/**
 * Date rules measured on the school's calendar.
 *
 * Laravel's `before_or_equal:today` resolves "today" from the server's
 * timezone, which is UTC. A teacher in Asia/Kolkata marking the register at
 * 7am is five and a half hours ahead of that, so on any morning before
 * 05:30 UTC the server would reject the date as being in the future. These
 * helpers pin the comparison to the acting school's date instead.
 */
trait ChecksSchoolDates
{
    /**
     * The acting school's current date, as Y-m-d.
     */
    protected function schoolToday(): string
    {
        return SchoolClock::forScope($this->user(), $this->input('school_id'))->date();
    }

    /**
     * "Today or earlier, at the school."
     */
    protected function notInFuture(): string
    {
        return 'before_or_equal:'.$this->schoolToday();
    }

    /**
     * "Today or later, at the school."
     */
    protected function notInPast(): string
    {
        return 'after_or_equal:'.$this->schoolToday();
    }
}

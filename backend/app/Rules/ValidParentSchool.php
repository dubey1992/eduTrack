<?php

namespace App\Rules;

use App\Models\School;
use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * Keeps a school group exactly one level deep.
 *
 * A parent with branches, and nothing below that. Groups of groups would mean
 * a recursive query everywhere a group is resolved - and everywhere that
 * forgot would silently miss half the group, which is the worst kind of
 * isolation bug because it looks like missing data rather than a leak.
 *
 * This is also the cheapest thing to get right and the dearest to fix: once
 * schools are linked in production, unpicking a three-deep tree means deciding
 * what somebody's records belonged to all along.
 */
class ValidParentSchool implements ValidationRule
{
    /**
     * @param  School|null  $subject  the school being edited, if this is an edit
     */
    public function __construct(private readonly ?School $subject = null) {}

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        if ($value === null || $value === '') {
            return;
        }

        $parent = School::query()->find($value);

        if ($parent === null) {
            // The `exists` rule alongside this one reports it properly.
            return;
        }

        if ($this->subject !== null && $parent->id === $this->subject->id) {
            $fail('A school cannot be a branch of itself.');

            return;
        }

        if ($parent->isBranch()) {
            $fail("\"{$parent->name}\" is itself a branch. A group is one level deep: pick its parent instead.");

            return;
        }

        if ($this->subject !== null && $this->subject->branches()->exists()) {
            $fail("\"{$this->subject->name}\" has branches of its own, so it cannot become a branch of another school.");
        }
    }
}

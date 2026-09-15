<?php

namespace App\Http\Requests\Concerns;

use App\Support\SchoolScope;
use Illuminate\Validation\Rule;

/**
 * The school a request writes into, and the rule guarding the field that
 * names it.
 *
 * Every form that creates something school-owned had its own copy of this,
 * and they had to agree: if the validation rule and the resolved id ever
 * disagreed, a record could be validated against one school and written into
 * another. One copy now, built on SchoolScope.
 */
trait ScopesSchool
{
    protected function schoolScope(): SchoolScope
    {
        return SchoolScope::for($this->user());
    }

    /**
     * The school this write lands in.
     *
     * Never simply what the client sent: an actor pinned to one school gets
     * that school whatever the request says (CLAUDE.md rule 10).
     */
    protected function resolvedSchoolId(): ?int
    {
        return $this->schoolScope()->writableSchoolId($this->requestedSchoolId());
    }

    /** What the request asked for, if anything. */
    protected function requestedSchoolId(): ?int
    {
        $value = $this->input('school_id');

        return $value === null || $value === '' ? null : (int) $value;
    }

    /**
     * Validation for the school_id field on a *read*.
     *
     * Unlike a write, "the whole group" is a sensible thing to ask for, so a
     * Group Admin may leave this out. A Super Admin still names one: every
     * school on the platform is not a report.
     *
     * @return array<int, mixed>
     */
    protected function readableSchoolIdRules(): array
    {
        $scope = $this->schoolScope();

        if ($scope->isUnrestricted()) {
            return ['required', 'integer', Rule::exists('schools', 'id')];
        }

        // Not scoped with an `exists` on purpose: everywhere else in the app
        // a school filter outside the actor's reach is ignored rather than
        // rejected, and a report must not be the one place that answers 422
        // to the same request.
        return ['nullable', 'integer'];
    }

    /**
     * Validation for the school_id field itself.
     *
     * An actor with exactly one school writes into it regardless, so the
     * field is ignored rather than checked. Anybody who could mean more than
     * one - a Super Admin, who belongs to none - has to name it.
     *
     * @return array<int, mixed>
     */
    protected function schoolIdRules(): array
    {
        $scope = $this->schoolScope();

        if ($scope->defaultSchoolId() !== null) {
            return ['nullable'];
        }

        return [
            'required',
            'integer',
            // Scoped, not bare: naming a school outside the actor's reach has
            // to fail validation rather than be silently ignored, or a write
            // would land somewhere they cannot see.
            Rule::exists('schools', 'id')->where(
                fn ($query) => $scope->isUnrestricted() ? $query : $query->whereIn('id', $scope->ids() ?? [])
            ),
        ];
    }
}

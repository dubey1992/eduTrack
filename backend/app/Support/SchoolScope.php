<?php

namespace App\Support;

use App\Enums\UserRole;
use App\Models\User;
use Illuminate\Contracts\Database\Query\Builder as BuilderContract;

/**
 * Which schools an actor is allowed to touch.
 *
 * This is the one question multi-tenancy turns on, and it used to be answered
 * inline - `$actor->role === UserRole::SuperAdmin || $actor->school_id === $x`
 * - in well over a hundred places. Every one of those was a chance to get
 * isolation wrong, and adding a role that spans several schools by editing all
 * of them by hand is how one school ends up reading another's records.
 *
 * So it is asked here instead, once. A SUPER_ADMIN is unrestricted; everybody
 * else is pinned to their own school. Nothing else knows the difference.
 *
 * Deliberately a value object with no query of its own: it is built from a
 * User that is already loaded, so resolving a scope costs nothing and can be
 * done freely inside a policy called once per record.
 */
final class SchoolScope
{
    /**
     * @param  array<int, int>|null  $schoolIds  null means every school there is
     */
    private function __construct(private readonly ?array $schoolIds) {}

    public static function for(User $actor): self
    {
        return match ($actor->role) {
            UserRole::SuperAdmin => self::unrestricted(),
            // A group admin is attached to the parent and reaches every
            // branch beneath it - and nothing outside that group, however
            // the request is edited.
            UserRole::GroupAdmin => self::of($actor->school?->groupSchoolIds() ?? []),
            // Everybody else lives in exactly one school. An account with no
            // school at all - which should not happen outside a half-finished
            // fixture - can see nothing, rather than mysteriously matching
            // every record whose school_id is also null.
            default => new self($actor->school_id === null ? [] : [$actor->school_id]),
        };
    }

    public static function unrestricted(): self
    {
        return new self(null);
    }

    /**
     * @param  array<int, int>  $schoolIds
     */
    public static function of(array $schoolIds): self
    {
        return new self(array_values(array_unique(array_map(intval(...), $schoolIds))));
    }

    /** True for an actor who belongs to no school and answers for all of them. */
    public function isUnrestricted(): bool
    {
        return $this->schoolIds === null;
    }

    /**
     * True when this scope covers several named schools - a group.
     *
     * The distinction a report needs: a group can be reported on as a whole
     * because it is a handful of branches, while "every school on the
     * platform" cannot, and a Super Admin is asked to name one.
     */
    public function coversAGroup(): bool
    {
        return $this->schoolIds !== null && count($this->schoolIds) > 1;
    }

    public function allows(?int $schoolId): bool
    {
        if ($this->isUnrestricted()) {
            return true;
        }

        return $schoolId !== null && in_array($schoolId, $this->schoolIds, true);
    }

    /**
     * The schools in scope, or null for every school.
     *
     * @return array<int, int>|null
     */
    public function ids(): ?array
    {
        return $this->schoolIds;
    }

    /**
     * The school a write lands in when the request does not name one.
     *
     * Null when that is genuinely ambiguous - an unrestricted actor, or one
     * who spans several schools - in which case the request has to say.
     */
    public function defaultSchoolId(): ?int
    {
        return $this->schoolIds !== null && count($this->schoolIds) === 1 ? $this->schoolIds[0] : null;
    }

    /**
     * Limits a query to what this actor may see, optionally narrowed further
     * to one school they asked for.
     *
     * A requested school can only narrow, never widen: one outside the scope
     * is ignored rather than honoured, which leaves the actor looking at their
     * own records instead of somebody else's. That is exactly what the
     * hand-written version did, and changing it would be a security decision
     * dressed up as a refactor.
     *
     * @template TBuilder of BuilderContract
     *
     * @param  TBuilder  $query
     * @return TBuilder
     */
    public function applyTo(BuilderContract $query, mixed $requested = null, string $column = 'school_id'): BuilderContract
    {
        $requested = self::requestedId($requested);

        if ($this->schoolIds !== null) {
            $query->whereIn($column, $this->schoolIds);
        }

        if ($requested !== null && $this->allows($requested)) {
            $query->where($column, $requested);
        }

        return $query;
    }

    /**
     * Reads a school id off a filter, which arrives as whatever was in the
     * query string.
     *
     * Absent or blank means no filter. Anything that is not a number becomes
     * 0 - an id no school has - so a nonsense filter matches nothing, which
     * is what `where('school_id', 'abc')` did before. It must never come out
     * as "no filter", or garbage would widen the result instead of narrowing
     * it.
     */
    private static function requestedId(mixed $value): ?int
    {
        if ($value === null || $value === '') {
            return null;
        }

        return is_numeric($value) ? (int) $value : 0;
    }

    /**
     * The school a write should be filed under, given what the request asked
     * for.
     *
     * An actor who may only write into one school writes into it whatever the
     * request says - the client's school_id is never trusted (CLAUDE.md rule
     * 10). An unrestricted one gets back exactly what they asked for, having
     * already had to pass validation that the school exists.
     */
    public function writableSchoolId(?int $requested): ?int
    {
        if ($this->isUnrestricted()) {
            return $requested;
        }

        if ($requested !== null && $this->allows($requested)) {
            return $requested;
        }

        return $this->defaultSchoolId();
    }
}

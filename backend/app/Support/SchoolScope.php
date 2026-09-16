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
 * Mostly a value object built from a User that is already loaded. The
 * exception is an admin role, which has to ask which schools are in its
 * group - so building one of those reads the `schools` table. Once per
 * request rather than once per check: the school relation is cached on the
 * User and the group on the School (see School::groupSchoolIds()), so a
 * policy called for every row in a list still pays for one query.
 *
 * That was not true before school groups existed, and the claim that it was
 * outlived the change by long enough to break a unit test that had no
 * database at all. Worth stating plainly rather than quietly.
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
            // Both admin roles answer for a whole group: a Group Admin from
            // the parent it is attached to, a School Admin from whichever
            // branch it sits in. Either way it is that school's group and
            // nothing outside it, however the request is edited.
            //
            // For a standalone school - which is most of them - the group is
            // just that school, so this resolves to exactly what it always
            // did and nothing about those schools changes.
            UserRole::GroupAdmin, UserRole::SchoolAdmin => self::groupOf($actor),
            // Everybody else lives in exactly one school. A Teacher at North
            // teaches at North; the group is an administrative idea, not a
            // teaching one. An account with no school at all - which should
            // not happen outside a half-finished fixture - can see nothing,
            // rather than mysteriously matching every record whose school_id
            // is also null.
            default => new self($actor->school_id === null ? [] : [$actor->school_id]),
        };
    }

    /**
     * The group an admin answers for: their school, plus its parent and
     * sisters, or its branches.
     *
     * Falls back to the school id on the account when the school itself
     * cannot be read - a row deleted out from under it, or a user built
     * without one. "Their own school and no other" is the right answer for an
     * admin whatever else is wrong; resolving to nothing would hide their own
     * records from them with no error to explain it.
     */
    private static function groupOf(User $actor): self
    {
        $group = $actor->school?->groupSchoolIds();

        if ($group === null) {
            return new self($actor->school_id === null ? [] : [$actor->school_id]);
        }

        return self::of($group);
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

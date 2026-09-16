<?php

namespace App\Services;

use App\Enums\SchoolStatus;
use App\Models\School;
use App\Models\User;
use App\Support\Pagination;
use App\Support\SchoolScope;
use Illuminate\Pagination\LengthAwarePaginator;

class SchoolService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(User $actor, array $filters = []): LengthAwarePaginator
    {
        return School::query()
            // The schools table is scoped on its own id, not a school_id
            // column: a Group Admin sees their group, a Super Admin sees all.
            ->tap(fn ($query) => SchoolScope::for($actor)->applyTo($query, null, 'id'))
            // Eager loaded so a list of branches does not fire a query per
            // row for the parent's name (CLAUDE.md rule 22).
            ->with('parent')
            ->withCount('branches')
            ->orderBy('name')
            // A tiebreaker, so a page boundary cannot fall in the middle of a
            // group of equal values and show one row twice while skipping
            // another. The ordering column above is not unique, and without
            // this the database is free to return ties in any order it likes -
            // which it does, differently, on MySQL and PostgreSQL.
            ->orderBy('id')
            ->paginate(perPage: Pagination::resolvePerPage($filters));
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function create(array $data): School
    {
        return School::create([
            ...$data,
            'status' => SchoolStatus::Active,
        ]);
    }

    /**
     * @param  array<string, mixed>  $data
     */
    public function update(School $school, array $data): School
    {
        $school->update($data);

        return $school;
    }

    public function activate(School $school): School
    {
        $school->update(['status' => SchoolStatus::Active]);

        return $school;
    }

    public function deactivate(School $school): School
    {
        $school->update(['status' => SchoolStatus::Inactive]);

        return $school;
    }
}

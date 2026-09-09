<?php

namespace App\Services;

use App\Enums\SchoolStatus;
use App\Models\School;
use App\Support\Pagination;
use Illuminate\Pagination\LengthAwarePaginator;

class SchoolService
{
    /**
     * @param  array<string, mixed>  $filters
     */
    public function paginate(array $filters = []): LengthAwarePaginator
    {
        return School::query()->orderBy('name')->paginate(perPage: Pagination::resolvePerPage($filters));
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

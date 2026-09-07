<?php

namespace App\Services;

use App\Enums\SchoolStatus;
use App\Models\School;
use Illuminate\Pagination\LengthAwarePaginator;

class SchoolService
{
    public function paginate(): LengthAwarePaginator
    {
        return School::query()->orderBy('name')->paginate(perPage: 20);
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

<?php

namespace App\Services\Imports;

use App\Models\User;
use App\Services\DriverService;
use App\Support\DateFormats;
use Illuminate\Validation\Rule;

/**
 * Drivers, with the licence expiry the transport office has to keep an eye
 * on.
 */
class DriverImporter implements RowImporter
{
    public function __construct(private readonly DriverService $drivers) {}

    public function label(): string
    {
        return 'Drivers';
    }

    public function headings(): array
    {
        return ['name', 'mobile', 'licence_number', 'licence_expiry'];
    }

    public function sample(): array
    {
        return ['Ramesh Yadav', '+91 98765 43210', 'MH1220260001234', '09/14/2029'];
    }

    public function rules(int $schoolId): array
    {
        return [
            'name' => ['required', 'string', 'max:150'],
            'mobile' => ['nullable', 'string', 'max:20', 'regex:/^\+[1-9][0-9 ]{6,17}$/'],
            'licence_number' => [
                'required', 'string', 'max:50',
                Rule::unique('drivers', 'licence_number')->where(fn ($query) => $query->where('school_id', $schoolId)),
            ],
            'licence_expiry' => ['nullable', 'date_format:'.DateFormats::INPUT_DATES],
        ];
    }

    public function uniqueColumns(): array
    {
        return ['licence_number'];
    }

    public function check(array $row, int $schoolId): array
    {
        return [];
    }

    public function import(array $row, int $schoolId, User $actor): ?array
    {
        $driver = $this->drivers->create([
            'school_id' => $schoolId,
            'name' => $row['name'],
            'mobile' => $row['mobile'],
            'licence_number' => $row['licence_number'],
            'licence_expiry' => $row['licence_expiry'] === null
                ? null
                : DateFormats::toIso((string) $row['licence_expiry']),
        ], $actor);

        return ['id' => $driver->id, 'name' => $driver->name];
    }
}

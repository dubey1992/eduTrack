<?php

namespace App\Services\Imports;

use App\Models\User;
use App\Services\VehicleService;
use Illuminate\Validation\Rule;

/**
 * The transport fleet.
 */
class VehicleImporter implements RowImporter
{
    public function __construct(private readonly VehicleService $vehicles) {}

    public function label(): string
    {
        return 'Vehicles';
    }

    public function headings(): array
    {
        return ['name', 'registration_number', 'capacity'];
    }

    public function sample(): array
    {
        return ['Bus 12', 'MH 12 AB 3456', '42'];
    }

    public function rules(int $schoolId): array
    {
        return [
            'name' => ['required', 'string', 'max:50'],
            'registration_number' => [
                'required', 'string', 'max:30',
                Rule::unique('vehicles', 'registration_number')->where(fn ($query) => $query->where('school_id', $schoolId)),
            ],
            'capacity' => ['required', 'integer', 'min:1', 'max:200'],
        ];
    }

    public function uniqueColumns(): array
    {
        return ['registration_number'];
    }

    public function check(array $row, int $schoolId): array
    {
        return [];
    }

    public function import(array $row, int $schoolId, User $actor): ?array
    {
        $vehicle = $this->vehicles->create([
            'school_id' => $schoolId,
            'name' => $row['name'],
            'registration_number' => $row['registration_number'],
            'capacity' => (int) $row['capacity'],
        ], $actor);

        return ['id' => $vehicle->id, 'name' => $vehicle->name];
    }
}

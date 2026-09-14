<?php

namespace App\Services\Imports;

use App\Models\Driver;
use App\Models\StaffProfile;
use App\Models\Student;
use App\Models\Subject;
use App\Models\Vehicle;

/**
 * Everything a school can upload in bulk, and what it takes to be allowed to.
 *
 * Each type names the model whose `create` policy already decides who may add
 * one of these by hand - importing a hundred of them is the same permission,
 * so there is no separate set of import rules to keep in step.
 */
class ImportRegistry
{
    /** @var array<string, array{importer: class-string<RowImporter>, model: class-string}> */
    private const array TYPES = [
        'students' => ['importer' => StudentImporter::class, 'model' => Student::class],
        'staff' => ['importer' => StaffImporter::class, 'model' => StaffProfile::class],
        'subjects' => ['importer' => SubjectImporter::class, 'model' => Subject::class],
        'vehicles' => ['importer' => VehicleImporter::class, 'model' => Vehicle::class],
        'drivers' => ['importer' => DriverImporter::class, 'model' => Driver::class],
    ];

    public function has(string $type): bool
    {
        return array_key_exists($type, self::TYPES);
    }

    /**
     * A fresh importer each time: they cache the school's departments and
     * sections while they work, which is only ever right for one import.
     */
    public function importer(string $type): RowImporter
    {
        return app(self::TYPES[$type]['importer']);
    }

    /** @return class-string */
    public function model(string $type): string
    {
        return self::TYPES[$type]['model'];
    }

    /** @return array<int, string> */
    public function types(): array
    {
        return array_keys(self::TYPES);
    }
}

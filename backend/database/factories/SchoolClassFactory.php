<?php

namespace Database\Factories;

use App\Models\AcademicYear;
use App\Models\School;
use App\Models\SchoolClass;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<SchoolClass>
 */
class SchoolClassFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'academic_year_id' => AcademicYear::factory(),
            // Unique regardless of level - several classes in the same
            // academic year would otherwise collide on (academic_year_id, name).
            'name' => 'Grade '.fake()->unique()->numerify('##'),
            'level' => fake()->numberBetween(1, 10),
        ];
    }

    public function forAcademicYear(AcademicYear $academicYear): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $academicYear->school_id,
            'academic_year_id' => $academicYear->id,
        ]);
    }
}

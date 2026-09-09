<?php

namespace Database\Factories;

use App\Models\AcademicYear;
use App\Models\School;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<AcademicYear>
 */
class AcademicYearFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        // Unique per school to avoid colliding on (school_id, name) when a
        // test creates several years for the same school.
        $startYear = fake()->unique()->numberBetween(2000, 2099);

        return [
            'school_id' => School::factory(),
            'name' => sprintf('%d-%d', $startYear, ($startYear + 1) % 100),
            'start_date' => "{$startYear}-04-01",
            'end_date' => ($startYear + 1).'-03-31',
            'is_current' => false,
        ];
    }

    public function current(): static
    {
        return $this->state(fn (array $attributes) => ['is_current' => true]);
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }
}

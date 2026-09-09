<?php

namespace Database\Factories;

use App\Models\Period;
use App\Models\School;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Period>
 */
class PeriodFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $number = fake()->unique()->numberBetween(1, 8);

        return [
            'school_id' => School::factory(),
            'period_number' => $number,
            'start_time' => sprintf('%02d:00', 7 + $number),
            'end_time' => sprintf('%02d:45', 7 + $number),
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function number(int $number): static
    {
        return $this->state(fn (array $attributes) => ['period_number' => $number]);
    }
}

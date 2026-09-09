<?php

namespace Database\Factories;

use App\Models\Holiday;
use App\Models\School;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Holiday>
 */
class HolidayFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $date = now()->addWeek()->toDateString();

        return [
            'school_id' => School::factory(),
            'name' => fake()->randomElement(['Independence Day', 'Founders Day', 'Diwali', 'Sports Day']),
            'type' => 'national',
            'start_date' => $date,
            'end_date' => $date,
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function onDates(string $start, ?string $end = null): static
    {
        return $this->state(fn (array $attributes) => ['start_date' => $start, 'end_date' => $end ?? $start]);
    }

    public function type(string $type): static
    {
        return $this->state(fn (array $attributes) => ['type' => $type]);
    }
}

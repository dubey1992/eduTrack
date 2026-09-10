<?php

namespace Database\Factories;

use App\Models\School;
use App\Models\Vehicle;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Vehicle>
 */
class VehicleFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'name' => 'Bus '.fake()->unique()->numberBetween(1, 99),
            'registration_number' => fake()->unique()->bothify('MH12 ?? ####'),
            'capacity' => 40,
            'status' => 'active',
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function capacity(int $capacity): static
    {
        return $this->state(fn (array $attributes) => ['capacity' => $capacity]);
    }

    public function inactive(): static
    {
        return $this->state(fn (array $attributes) => ['status' => 'inactive']);
    }
}

<?php

namespace Database\Factories;

use App\Models\Driver;
use App\Models\School;
use App\Models\TransportRoute;
use App\Models\Vehicle;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<TransportRoute>
 */
class TransportRouteFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_id' => School::factory(),
            'name' => fake()->unique()->streetName().' Route',
            'vehicle_id' => null,
            'driver_id' => null,
            'status' => 'active',
        ];
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $school->id]);
    }

    public function withVehicle(Vehicle $vehicle): static
    {
        return $this->state(fn (array $attributes) => ['vehicle_id' => $vehicle->id]);
    }

    public function withDriver(Driver $driver): static
    {
        return $this->state(fn (array $attributes) => ['driver_id' => $driver->id]);
    }

    public function inactive(): static
    {
        return $this->state(fn (array $attributes) => ['status' => 'inactive']);
    }
}

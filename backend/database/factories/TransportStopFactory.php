<?php

namespace Database\Factories;

use App\Models\TransportRoute;
use App\Models\TransportStop;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<TransportStop>
 */
class TransportStopFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'route_id' => TransportRoute::factory(),
            'school_id' => fn (array $attributes) => TransportRoute::findOrFail($attributes['route_id'])->school_id,
            'name' => fake()->unique()->streetName().' Stop',
            'sequence_number' => 1,
            'pickup_time' => '07:30',
            'drop_time' => '15:30',
        ];
    }

    public function forRoute(TransportRoute $route): static
    {
        return $this->state(fn (array $attributes) => ['school_id' => $route->school_id, 'route_id' => $route->id]);
    }

    public function atSequence(int $sequenceNumber): static
    {
        return $this->state(fn (array $attributes) => ['sequence_number' => $sequenceNumber]);
    }
}

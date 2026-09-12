<?php

namespace Database\Factories;

use App\Models\Driver;
use App\Models\School;
use App\Models\TransportRoute;
use App\Models\TransportTrip;
use App\Models\User;
use App\Models\Vehicle;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<TransportTrip>
 */
class TransportTripFactory extends Factory
{
    /**
     * The route, vehicle, driver and starter are only built when the caller
     * did not supply them (states such as forRoute() override these keys
     * before the closures below are ever evaluated).
     *
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'route_id' => fn () => $this->makeReadyRoute()->id,
            'school_id' => fn (array $attributes) => $this->route($attributes)->school_id,
            'vehicle_id' => fn (array $attributes) => $this->route($attributes)->vehicle_id,
            'driver_id' => fn (array $attributes) => $this->route($attributes)->driver_id,
            'trip_date' => now()->toDateString(),
            'direction' => 'pickup',
            'status' => 'in_progress',
            'current_stop_id' => null,
            'started_by' => fn (array $attributes) => User::factory()
                ->forSchool(School::findOrFail($attributes['school_id']))
                ->create()
                ->id,
            'started_at' => now(),
            'ended_at' => null,
        ];
    }

    /**
     * A brand-new route with an active vehicle and driver attached.
     */
    private function makeReadyRoute(): TransportRoute
    {
        $route = TransportRoute::factory()->create();
        $vehicle = Vehicle::factory()->forSchool($route->school)->create();
        $driver = Driver::factory()->forSchool($route->school)->create();
        $route->update(['vehicle_id' => $vehicle->id, 'driver_id' => $driver->id]);

        return $route->refresh();
    }

    /**
     * @param  array<string, mixed>  $attributes
     */
    private function route(array $attributes): TransportRoute
    {
        return TransportRoute::findOrFail($attributes['route_id']);
    }

    /**
     * For a route that already has its vehicle and driver attached.
     */
    public function forRoute(TransportRoute $route): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $route->school_id,
            'route_id' => $route->id,
            'vehicle_id' => $route->vehicle_id,
            'driver_id' => $route->driver_id,
        ]);
    }

    public function startedBy(User $user): static
    {
        return $this->state(fn (array $attributes) => ['started_by' => $user->id]);
    }

    public function direction(string $direction): static
    {
        return $this->state(fn (array $attributes) => ['direction' => $direction]);
    }

    public function onDate(string $date): static
    {
        return $this->state(fn (array $attributes) => ['trip_date' => $date]);
    }

    public function completed(): static
    {
        return $this->state(fn (array $attributes) => ['status' => 'completed', 'ended_at' => now()]);
    }

    public function cancelled(): static
    {
        return $this->state(fn (array $attributes) => ['status' => 'cancelled', 'ended_at' => now()]);
    }
}

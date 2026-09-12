<?php

namespace Database\Factories;

use App\Enums\SchoolStatus;
use App\Models\School;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<School>
 */
class SchoolFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'name' => fake()->company().' School',
            'registration_number' => fake()->bothify('REG-####??'),
            'email' => fake()->unique()->companyEmail(),
            'phone' => fake()->numerify('+91 ##########'),
            'address' => fake()->streetAddress(),
            'city' => fake()->city(),
            'state' => fake()->state(),
            'country' => fake()->country(),
            'postal_code' => fake()->postcode(),
            'currency_code' => fake()->randomElement(['INR', 'USD', 'GBP', 'NGN', 'AED']),
            // UTC by default so existing tests keep asserting against the
            // server's clock; a test that cares about timezones sets its own.
            'timezone' => 'UTC',
            'status' => SchoolStatus::Active,
        ];
    }

    public function inactive(): static
    {
        return $this->state(fn (array $attributes) => ['status' => SchoolStatus::Inactive]);
    }
}

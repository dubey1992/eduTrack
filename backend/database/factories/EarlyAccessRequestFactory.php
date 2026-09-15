<?php

namespace Database\Factories;

use App\Enums\EarlyAccessStatus;
use App\Models\EarlyAccessRequest;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<EarlyAccessRequest>
 */
class EarlyAccessRequestFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        return [
            'school_name' => fake()->company().' School',
            'contact_name' => fake()->name(),
            'contact_role' => fake()->randomElement(['Principal', 'Director', 'IT Head', null]),
            'email' => fake()->unique()->companyEmail(),
            'phone' => fake()->numerify('+91 ##########'),
            'city' => fake()->city(),
            'country' => 'India',
            'expected_students' => fake()->numberBetween(80, 4000),
            'current_software' => fake()->randomElement(['Spreadsheets', 'Nothing yet', null]),
            'message' => null,
            'status' => EarlyAccessStatus::New,
        ];
    }

    public function status(EarlyAccessStatus $status): static
    {
        return $this->state(fn (array $attributes) => ['status' => $status]);
    }
}

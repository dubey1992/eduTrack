<?php

namespace Database\Factories;

use App\Enums\PaymentMode;
use App\Enums\PaymentStatus;
use App\Enums\PaymentType;
use App\Models\Payment;
use App\Models\School;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Payment>
 */
class PaymentFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $school = School::factory();

        return [
            'school_id' => $school,
            'payment_type' => fake()->randomElement(PaymentType::cases()),
            'amount' => fake()->randomFloat(2, 1000, 500000),
            'currency_code' => 'INR',
            'payment_date' => fake()->dateTimeBetween('-6 months', 'now')->format('Y-m-d'),
            'payment_mode' => fake()->randomElement(PaymentMode::cases()),
            'reference_number' => fake()->bothify('REF-########'),
            'notes' => null,
            'status' => PaymentStatus::Paid,
            'created_by' => User::factory(),
        ];
    }

    public function status(PaymentStatus $status): static
    {
        return $this->state(fn (array $attributes) => ['status' => $status]);
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $school->id,
            'currency_code' => $school->currency_code,
        ]);
    }
}

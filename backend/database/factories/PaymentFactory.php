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
        $amount = fake()->randomFloat(2, 1000, 500000);

        return [
            'school_id' => $school,
            'payment_type' => fake()->randomElement(PaymentType::cases()),
            'amount' => $amount,
            'paid_amount' => $amount,
            'currency_code' => 'INR',
            'payment_date' => fake()->dateTimeBetween('-6 months', 'now')->format('Y-m-d'),
            'payment_mode' => fake()->randomElement(PaymentMode::cases()),
            'reference_number' => fake()->bothify('REF-########'),
            'notes' => null,
            'status' => PaymentStatus::Paid,
            'created_by' => User::factory(),
        ];
    }

    /**
     * Keeps the money in step with the status.
     *
     * This runs after `create()`'s overrides are merged, which a state
     * closure does not - a state reading `$attributes['amount']` sees the
     * factory's random figure, not the one the test actually asked for, and
     * silently builds a payment whose status and money disagree. The
     * application cannot produce such a row, so the factory must not either:
     * a test built on one proves nothing.
     */
    public function configure(): static
    {
        return $this->afterMaking(function (Payment $payment) {
            $amount = (float) $payment->amount;
            $paid = (float) $payment->paid_amount;

            $payment->paid_amount = match ($payment->status) {
                PaymentStatus::Paid => $amount,
                PaymentStatus::Pending, PaymentStatus::Cancelled => 0,
                // A part-payment keeps whatever the test chose, as long as it
                // really is a part; anything else falls back to half.
                PaymentStatus::Partial => $paid > 0 && $paid < $amount ? $paid : round($amount / 2, 2),
            };
        });
    }

    public function status(PaymentStatus $status): static
    {
        return $this->state(fn (array $attributes) => ['status' => $status]);
    }

    /**
     * A part-payment with a specific amount still owed.
     */
    public function partiallyPaid(float $paidAmount): static
    {
        return $this->state(fn (array $attributes) => [
            'status' => PaymentStatus::Partial,
            'paid_amount' => $paidAmount,
        ]);
    }

    public function forSchool(School $school): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $school->id,
            'currency_code' => $school->currency_code,
        ]);
    }
}

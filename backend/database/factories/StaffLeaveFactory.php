<?php

namespace Database\Factories;

use App\Models\StaffLeave;
use App\Models\StaffProfile;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<StaffLeave>
 */
class StaffLeaveFactory extends Factory
{
    /**
     * @return array<string, mixed>
     */
    public function definition(): array
    {
        $staffProfile = StaffProfile::factory()->create();

        return [
            'school_id' => $staffProfile->school_id,
            'staff_profile_id' => $staffProfile->id,
            'leave_type' => 'casual',
            'start_date' => now()->addDay()->toDateString(),
            'end_date' => now()->addDay()->toDateString(),
            'reason' => $this->faker->sentence(),
            'status' => 'pending',
            'applied_by' => $staffProfile->user_id,
            'reviewed_by' => null,
            'review_remarks' => null,
        ];
    }

    public function forStaff(StaffProfile $staffProfile): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $staffProfile->school_id,
            'staff_profile_id' => $staffProfile->id,
            'applied_by' => $staffProfile->user_id,
        ]);
    }

    public function onDates(string $start, string $end): static
    {
        return $this->state(fn (array $attributes) => ['start_date' => $start, 'end_date' => $end]);
    }

    public function status(string $status): static
    {
        return $this->state(fn (array $attributes) => ['status' => $status]);
    }
}

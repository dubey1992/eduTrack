<?php

namespace Database\Factories;

use App\Models\StaffAttendance;
use App\Models\StaffProfile;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<StaffAttendance>
 */
class StaffAttendanceFactory extends Factory
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
            'attendance_date' => now()->toDateString(),
            'status' => 'present',
            'check_in' => null,
            'check_out' => null,
            'remarks' => null,
            'marked_by' => null,
        ];
    }

    public function forStaff(StaffProfile $staffProfile): static
    {
        return $this->state(fn (array $attributes) => [
            'school_id' => $staffProfile->school_id,
            'staff_profile_id' => $staffProfile->id,
        ]);
    }

    public function onDate(string $date): static
    {
        return $this->state(fn (array $attributes) => ['attendance_date' => $date]);
    }

    public function status(string $status): static
    {
        return $this->state(fn (array $attributes) => ['status' => $status]);
    }
}
